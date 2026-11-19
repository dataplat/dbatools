#nullable enable

using System;
using System.Management.Automation;
using System.Net;
using System.Security;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates OAuth2 access tokens for Azure SQL Database and other Azure services authentication.
/// </summary>
/// <remarks>
/// Port of public/New-DbaAzAccessToken.ps1 at the pin. Tokens come from AzureAccessTokenService over plain HTTP:
/// ManagedIdentity asks the Azure Instance Metadata Service, ServicePrincipal and RenewableServicePrincipal ask
/// Microsoft Entra ID with the client credentials grant. No PowerShell runs.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAzAccessToken")]
public sealed class NewDbaAzAccessTokenCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>
    /// Specifies the authentication method for generating the access token. ManagedIdentity uses Azure VM identity for password-free authentication, ServicePrincipal uses application credentials for automated scripts, and RenewableServicePrincipal creates tokens that automatically refresh for long-running connections.
    /// </summary>
    [Parameter(Mandatory = true, Position = 0)]
    [PsStringCast]
    [ValidateSet("ManagedIdentity", "ServicePrincipal", "RenewableServicePrincipal")]
    public string Type { get; set; } = null!;

    /// <summary>
    /// Determines which Azure service resource to generate the token for. AzureSqlDb creates tokens for Azure SQL Database connections, while other options like KeyVault, Storage, and ResourceManager target their respective Azure services. Defaults to AzureSqlDb for database connections.
    /// </summary>
    // The duplicate ResourceManager entry is preserved from the pinned ValidateSet.
    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidateSet("AzureSqlDb", "ResourceManager", "DataLake", "EventHubs", "KeyVault", "ResourceManager", "ServiceBus", "Storage")]
    public string Subtype { get; set; } = "AzureSqlDb";

    /// <summary>
    /// Optional configuration object for advanced token generation scenarios. Typically auto-generated based on the Subtype parameter and rarely needs manual specification. Use this only when you need custom resource URLs or API versions not covered by standard subtypes.
    /// </summary>
    [Parameter(Position = 2)]
    public object? Config { get; set; }

    /// <summary>
    /// When using the ServicePrincipal type, a Credential is required. The username is the App ID and Password is the App Password
    ///
    /// https://docs.microsoft.com/en-us/azure/active-directory/user-help/multi-factor-authentication-end-user-app-passwords
    /// </summary>
    // [Credential]: the pinned [PSCredential] function parameter takes an App ID string and prompts for the secret.
    [Parameter(Position = 3)]
    [Credential]
    public PSCredential? Credential { get; set; }

    /// <summary>
    /// Specifies the Azure Active Directory tenant ID or domain name for Service Principal authentication. Required when using ServicePrincipal or RenewableServicePrincipal types. Use your organization's tenant ID (GUID format) or domain name like 'contoso.onmicrosoft.com'.
    /// </summary>
    [Parameter(Position = 4)]
    public string? Tenant { get; set; }

    /// <summary>
    /// Certificate thumbprint for Managed Service Identity authentication. Use this when your Azure VM or service uses certificate-based authentication instead of the default metadata endpoint. Defaults to the value stored in dbatools configuration.
    /// </summary>
    [Parameter(Position = 5)]
    public string? Thumbprint { get; set; }

    /// <summary>
    /// Specifies the certificate store location for MSI certificates. Choose CurrentUser for user-specific certificates or LocalMachine for system-wide certificates. Use with Thumbprint parameter for certificate-based Managed Service Identity authentication.
    /// </summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    [ValidateSet("CurrentUser", "LocalMachine")]
    public string? Store { get; set; }

    private const string SqlDatabaseResource = "https://database.windows.net/";

    private string _resource = SqlDatabaseResource;
    private string? _apiVersion;

    /// <summary>Applies the configuration defaults, checks the service principal input and picks the resource.</summary>
    protected override void BeginProcessing()
    {
        // The pinned parameter defaults read the configuration at bind time; the [string] cast turns null into "".
        if (!TestBound("Tenant"))
            Tenant = ConfigString("azure.tenantid");
        if (!TestBound("Thumbprint"))
            Thumbprint = ConfigString("azure.certificate.thumbprint");
        if (!TestBound("Store"))
            Store = ConfigString("azure.certificate.store");

        if (IsType("ServicePrincipal") || IsType("RenewableServicePrincipal"))
        {
            object? appid = ConnectionService.GetConfigurationValue("azure.appid");
            object? clientsecret = ConnectionService.GetConfigurationValue("azure.clientsecret");

            if (LanguagePrimitives.IsTrue(appid) && LanguagePrimitives.IsTrue(clientsecret) && Credential is null)
            {
                // PS: New-Object PSCredential ($appid, $clientsecret), outside any try. A secret that is not a SecureString
                // fails that statement: a plain call writes New-Object's record and goes on with no credential, a caller's
                // try catches it, -EnableException stops here.
                ErrorRecord? constructorFault = null;
                PSCredential? configured = BuildConfigCredential(appid!, clientsecret!, ref constructorFault);
                if (constructorFault is not null)
                    SurfaceFault(constructorFault);
                else
                    Credential = configured;
            }

            if (Credential is null && String.IsNullOrEmpty(Tenant))
            {
                StopFunction("You must specify a Credential and Tenant when using ServicePrincipal or RenewableServicePrincipal");
                return;
            }
        }

        ResolveTokenRequest();
    }

    /// <summary>Requests the token or builds the renewable token.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        try
        {
            if (IsType("ManagedIdentity"))
            {
                AzureAccessToken token = AzureAccessTokenService.GetManagedIdentityToken(_resource, _apiVersion!);
                WriteObject(token.AccessToken);
            }
            else if (IsType("ServicePrincipal"))
            {
                RequestServicePrincipalToken();
            }
            else if (IsType("RenewableServicePrincipal"))
            {
                PsObjectIRenewableToken renewable = new PsObjectIRenewableToken
                {
                    ClientSecret = RequireCredential().GetNetworkCredential().Password,
                    Resource = _resource,
                    Tenant = Tenant,
                    UserId = RequireCredential().UserName,
                };
                WriteObject(renewable);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // No -Continue here: this block has no enclosing loop, so the continue would escape the command
            // and eat an iteration of whatever loop the caller runs in (#10638).
            StopFunction("Failure", errorRecord: CaughtRecord(ex));
        }
    }

    /// <summary>
    /// Picks the resource and the managed identity api-version. A bound -Config names them (Resource, Version), as its
    /// help promises; whatever it leaves out comes from the Subtype and the default api-version. The pinned begin block
    /// replaced $Config with the Subtype's one-key table, so a caller's -Config never took effect (correction
    /// config-ignored).
    /// </summary>
    private void ResolveTokenRequest()
    {
        bool configBound = TestBound("Config");
        string? configuredResource = configBound ? AzureAccessTokenService.ReadConfigValue(Config, "Resource") : null;
        _resource = String.IsNullOrEmpty(configuredResource) ? SubtypeResource(Subtype) : configuredResource!;
        _apiVersion = configBound ? AzureAccessTokenService.ReadConfigValue(Config, "Version") : null;
    }

    /// <summary>
    /// Asks the tenant's token endpoint for a token with the service principal's client credentials, on both editions.
    /// The pinned branch refused PowerShell 7 and, on Windows PowerShell, needed ADAL, which no longer ships, so the
    /// documented form returned no token anywhere (correction service-principal-token).
    /// </summary>
    private void RequestServicePrincipalToken()
    {
        PSCredential credential = RequireCredential();
        AzureAccessToken token = AzureAccessTokenService.GetClientCredentialToken(AzureAccessTokenService.Authority, Tenant,
            credential.UserName, credential.GetNetworkCredential().Password, _resource);
        WriteObject(token.AccessToken);
    }

    private static string SubtypeResource(string subtype)
    {
        switch ((subtype ?? String.Empty).ToLowerInvariant())
        {
            case "resourcemanager":
                return "https://management.azure.com/";
            case "keyvault":
                return "https://vault.azure.net/";
            case "datalake":
                return "https://datalake.azure.net/";
            case "eventhubs":
                return "https://eventhubs.azure.net/";
            case "servicebus":
                return "https://servicebus.azure.net/";
            case "storage":
                return "https://storage.azure.com/";
            default:
                return SqlDatabaseResource;
        }
    }

    private PSCredential RequireCredential()
    {
        // The pinned function calls $Credential.GetNetworkCredential() here; without a credential that fails inside the
        // try with PowerShell's InvokeMethodOnNull record (InvalidOperation) and warns "Failure".
        if (Credential is not null)
            return Credential;
        RuntimeException nullFailure = new("You cannot call a method on a null-valued expression.");
        throw new RuntimeException(nullFailure.Message, null,
            new ErrorRecord(nullFailure, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
    }

    private bool IsType(string value)
    {
        return String.Equals(Type, value, StringComparison.OrdinalIgnoreCase);
    }

    private static string ConfigString(string fullName)
    {
        return LanguagePrimitives.ConvertTo<string>(ConnectionService.GetConfigurationValue(fullName)) ?? String.Empty;
    }

    /// <summary>
    /// The pinned New-Object PSCredential ($appid, $clientsecret): the secret must already be a SecureString, as the
    /// PSCredential constructor requires. Anything else gives New-Object's ConstructorInvokedThrowException record
    /// (InvalidOperation) and no credential.
    /// </summary>
    private static PSCredential? BuildConfigCredential(object appid, object clientsecret, ref ErrorRecord? fault)
    {
        object secret = clientsecret is PSObject wrapped ? wrapped.BaseObject : clientsecret;
        if (secret is SecureString secure)
            return new PSCredential(LanguagePrimitives.ConvertTo<string>(appid), secure);
        MethodException overload = new("Cannot find an overload for \"PSCredential\" and the argument count: \"2\".");
        fault = new ErrorRecord(overload, "ConstructorInvokedThrowException", ErrorCategory.InvalidOperation, null);
        return null;
    }

    // A statement of the pin's begin block, which has no try around it: a plain call writes the record and goes on, a
    // caller's try catches it, -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a begin-block statement fault, outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }

    private static ErrorRecord CaughtRecord(Exception ex)
    {
        if (ex is RuntimeException runtime && runtime.ErrorRecord is not null)
            return runtime.ErrorRecord;
        if (ex is WebException || ex is InvalidOperationException)
        {
            // PS: the pinned managed identity request is Invoke-WebRequest -ErrorAction Stop, whose failed request raises
            // WebCmdletWebResponseException (InvalidOperation) around the transport's exception: a WebException on Windows
            // PowerShell, an HttpRequestException on PowerShell 7 (probe pin-azfaults-20261111). Stop-Function keeps that
            // category. HttpWebRequest on .NET 8 wraps the HttpRequestException in a WebException; the record carries the
            // HttpRequestException there, as PowerShell 7 does.
            Exception reported = AzureAccessTokenService.ReportedRequestFailure(ex);
            return new ErrorRecord(reported, "WebCmdletWebResponseException", ErrorCategory.InvalidOperation, null);
        }
        return new ErrorRecord(ex, "New-DbaAzAccessToken", ErrorCategory.NotSpecified, null);
    }
}
