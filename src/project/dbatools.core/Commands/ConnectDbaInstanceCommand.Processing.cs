#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Language;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.TabExpansion;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class ConnectDbaInstanceCommand
{
    // The request every instance is resolved with; built on the first record, after the pinned token step replaced
    // Tenant, SqlCredential and AccessToken (pinned 552-554).
    private SmoConnectionRequest? _request;
    // Pinned $tryconnstring: set by the process block and never reset, so later pipeline input keeps it.
    private bool _tryConnString = false;
    // Pinned $PSBoundParameters.AccessToken = $AccessToken (pinned 554): the token counts as bound from then on.
    private bool _syntheticAccessTokenBound = false;

    protected override void BeginProcessing()
    {
        // Pinned 482-490 refuse a SqlCredential of another type; the binder types it PSCredential, so that cannot happen.

        // In an unusual move, Connect-DbaInstance goes the exact opposite way of all commands when it comes to exceptions
        // this means that by default it Stop-Function -Messages, but do not be tempted to Stop-Function -Message
        // -EnableException (not in the pin; see its declaration) decides only without -DisableException, so a
        // $PSDefaultParameterValues entry for it, which the pinned function never saw, cannot overrule -DisableException.
        if (DisableException.IsPresent || !TestBound(nameof(EnableException)))
            EnableException = new SwitchParameter(!DisableException.IsPresent);

        // [string]$Tenant = (Get-DbatoolsConfigValue -FullName 'azure.tenantid')
        if (!TestBound(nameof(Tenant)))
            Tenant = LanguagePrimitives.ConvertTo<string>(ConnectionService.GetConfigurationValue("azure.tenantid"));

        // The rest of the pinned begin block (the loaded SMO version, the SetDefaultInitFields field lists and the
        // AzureDomain escape) lives in ConnectionService; the other parameter defaults are applied by the request.
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: -in is case-insensitive and ValidateSet passes the user's casing through
        // (cross-model review 2026-07-07 finding 1).
        if (ConnectionService.RequiresSqlCredential(AuthenticationType) && SqlCredential is null)
        {
            StopFunction("AuthenticationType " + AuthenticationType + " requires SqlCredential.");
            return;
        }

        // if tenant is specified with a GUID username such as 21f5633f-6776-4bab-b878-bbd5e3e5ed72 (for clientid)
        // PS: -not $AccessToken is truthiness, so an empty-string token counts as absent
        // (cross-model review 2026-07-07 finding 3).
        // Which strategy this framework supports is the service's call, not the command's.
        ServicePrincipalPlan? servicePrincipalPlan = ConnectionService.PlanServicePrincipalConnection(Tenant, AccessToken, SqlCredential);
        if (servicePrincipalPlan is not null)
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, servicePrincipalPlan.VerboseMessage);
                if (servicePrincipalPlan.Strategy == ServicePrincipalStrategy.ConnectionStringRewrite)
                {
                    _tryConnString = true;
                }
                else
                {
                    // Pinned 549: (New-DbaAzAccessToken -Type RenewableServicePrincipal -Subtype AzureSqlDb -Tenant $Tenant
                    // -Credential $SqlCredential -ErrorAction Stop).GetAccessToken(). The renewable token that
                    // New-DbaAzAccessToken's port returns for those arguments, asked here for its access token.
                    string token = ConnectionService.NewServicePrincipalToken(Tenant!, SqlCredential!).GetAccessToken();
                    AccessToken = new PSObject(token);
                    // PS: $PSBoundParameters.Tenant = $Tenant = $null; $PSBoundParameters.SqlCredential = $SqlCredential = $null;
                    //     $PSBoundParameters.AccessToken = $AccessToken
                    Tenant = null;
                    SqlCredential = null;
                    _syntheticAccessTokenBound = true;
                }
            }
            catch (Exception ex)
            {
                string? errormessage = ConnectionService.GetDeepErrorMessage(ex);
                StopFunction("Failed to get access token for Azure SQL DB (" + errormessage + ")");
                return;
            }
        }

        WriteMessage(MessageLevel.Debug, "Starting process block");

        _request ??= BuildRequest();

        foreach (DbaInstanceParameter givenInstance in SqlInstance)
        {
            DbaInstanceParameter instance = givenInstance;

            if (_tryConnString)
            {
                // Pinned 569-575: the instance becomes an Active Directory Service Principal connection string (PR #7610),
                // built with SqlConnectionStringBuilder so the secret cannot add keywords.
                string azureserver = instance.InputObject.ToString()!;
                string clientSecret = SqlCredential!.GetNetworkCredential().Password;
                instance = new DbaInstanceParameter(ConnectionService.BuildServicePrincipalConnectionString(azureserver, _request.Database, SqlCredential.UserName, clientSecret));
            }

            // The pinned "Starting loop" message is written before that replacement, so it names the instance as given.
            _request.LoopInstance = givenInstance;
            _request.Instance = instance;

            ConnectionResolution resolution;
            try
            {
                resolution = ConnectionService.ResolveInstance(_request);
            }
            catch (ConnectionResolutionException ex)
            {
                switch (ex.Kind)
                {
                    case ConnectionResolutionFailure.ConnectFailure:
                        // Pinned 1500: Stop-Function -Target $instance -Message "Failure" -Category ConnectionError -ErrorRecord $connectionError -Continue
                        StopFunction("Failure", target: instance, errorRecord: BuildConnectionErrorRecord(ex, instance), category: ErrorCategory.ConnectionError, continueLoop: true);
                        continue;
                    case ConnectionResolutionFailure.AzureUnsupported:
                    case ConnectionResolutionFailure.UnsupportedVersion:
                    case ConnectionResolutionFailure.MinimumVersion:
                    case ConnectionResolutionFailure.AccessTokenConversion:
                    case ConnectionResolutionFailure.CopiedContextRefused:
                        // Stop-Function -Target $instance -Message <the service's verbatim message> -Continue: "Azure SQL
                        // Database not supported" (pinned 1508), the SQL Server 2005 refusal (dbatools PR 10813), "SQL
                        // Server version N required - X not supported." (1550), the SecureString token conversion
                        // (1330, 1341), and the copied context's refusals (970, 977).
                        StopFunction(ex.Message, target: instance, continueLoop: true);
                        continue;
                    case ConnectionResolutionFailure.WindowsCredentialOnUnix:
                    default:
                        // Pinned 1308-1311: Stop-Function -Target $instance -Message "Cannot use Windows credentials ..." followed by
                        // return - the remaining instances are NOT processed (no -Continue in the source).
                        StopFunction(ex.Message, target: instance);
                        return;
                }
            }
            catch (Exception ex) when (ex is not PipelineStoppedException && ex is not ActionPreferenceStopException)
            {
                // Any other failure (an AppendConnectionString SqlClient cannot parse, a passed-in server that cannot reconnect)
                // stops only this instance, as a failing statement did in the pinned loop. The pin then went on with a
                // connection missing what was asked for; this reports the instance as failed instead.
                StopFunction("Failure", target: instance, exception: ex, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            if (resolution.SqlConnection is not null)
            {
                // Pinned 1554-1563: the hash registration ran in the service; then the reference, then the SqlConnection.
                SetNewConnectionReference(resolution.IsNewConnection);
                WriteObject(resolution.SqlConnection);
                continue;
            }

            // Pinned 1610-1614
            SetNewConnectionReference(resolution.IsNewConnection);
            WriteObject(resolution.Server);

            if (resolution.IsNewConnection && !DedicatedAdminConnection)
            {
                if (!resolution.UsesCredentialSspiProvider)
                {
                    // Register the connected instance, so that the TEPP updater knows it's been connected to and starts building the cache
                    ConnectionService.RegisterInstanceForTepp(resolution.Instance, resolution.Server);

                    // Update lots of registered stuff
                    // Default for [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled is $true, so will not run by default
                    // Must be explicitly activated with [Dataplat.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $false to run
                    if (!TabExpansionHost.TeppSyncDisabled)
                    {
                        // Variable $FullSmoName is used inside the script blocks, so we have to set
                        string fullSmoName = resolution.Instance.FullSmoName.ToLowerInvariant();
                        WriteMessage(MessageLevel.Debug, "Will run Invoke-TEPPCacheUpdate for FullSmoName = " + fullSmoName);
                        foreach (ScriptBlock scriptBlock in TabExpansionHost.TeppGatherScriptsFast.ToArray())
                        {
                            InvokeTeppCacheUpdate(scriptBlock, fullSmoName, resolution.Server);
                        }
                    }
                }

                // By default, SMO initializes several properties. We push it to the limit and gather a bit more
                ConnectionService.ApplyDefaultInitFields(resolution.Server, resolution.IsAzure, MessageSink);
            }

            if (!resolution.UsesCredentialSspiProvider)
            {
                ConnectionService.RegisterConnection(resolution.Server.ConnectionContext.ConnectionString, resolution.Server, MessageSink);
            }
            WriteMessage(MessageLevel.Debug, "We are finished with this instance");
        }
    }

    private void SetNewConnectionReference(bool isNewConnection)
    {
        // if ($IsNewConnectionReference) { $IsNewConnectionReference.Value = $isNewConnection }
        if (IsNewConnectionReference is not null)
        {
            IsNewConnectionReference.Value = isNewConnection;
        }
    }

    private SmoConnectionRequest BuildRequest()
    {
        SmoConnectionRequest request = new()
        {
            SqlCredential               = SqlCredential,
            Database                    = Database,
            ApplicationIntent           = ApplicationIntent,
            AzureUnsupported            = AzureUnsupported,
            BatchSeparator              = BatchSeparator,
            ClientName                  = ClientName,
            ConnectRetryCount           = ConnectRetryCount,
            ConnectRetryInterval        = ConnectRetryInterval,
            ConnectTimeout              = ConnectTimeout,
            EncryptConnection           = EncryptConnection,
            FailoverPartner             = FailoverPartner,
            LockTimeout                 = LockTimeout,
            MaxPoolSize                 = MaxPoolSize,
            MinPoolSize                 = MinPoolSize,
            MinimumVersion              = MinimumVersion,
            MultipleActiveResultSets    = MultipleActiveResultSets,
            MultiSubnetFailover         = MultiSubnetFailover,
            NetworkProtocol             = NetworkProtocol,
            NonPooledConnection         = NonPooledConnection,
            PacketSize                  = PacketSize,
            PooledConnectionLifetime    = PooledConnectionLifetime,
            SqlExecutionModes           = SqlExecutionModes,
            StatementTimeout            = StatementTimeout,
            TrustServerCertificate      = TrustServerCertificate,
            AllowTrustServerCertificate = AllowTrustServerCertificate,
            WorkstationId               = WorkstationId,
            AlwaysEncrypted             = AlwaysEncrypted,
            AppendConnectionString      = AppendConnectionString,
            SqlConnectionOnly           = SqlConnectionOnly,
            AzureDomain                 = AzureDomain,
            AccessToken                 = AccessToken,
            AuthenticationType          = AuthenticationType,
            DedicatedAdminConnection    = DedicatedAdminConnection,
            MessageCallback             = MessageSink
        };

        HashSet<string> bound = new(StringComparer.OrdinalIgnoreCase);
        foreach (string key in MyInvocation.BoundParameters.Keys)
        {
            bound.Add(key);
        }
        if (_syntheticAccessTokenBound)
        {
            // PS: $PSBoundParameters.AccessToken = $AccessToken after the token acquisition -
            // the key becomes "bound" for the Test-Bound checks of the ignored-parameter warnings.
            bound.Add("AccessToken");
        }
        request.BoundParameters = bound;

        // The Get-DbatoolsConfigValue parameter defaults of the pinned param block, resolved for everything the
        // caller did not bind.
        request.ApplyConfigurationDefaults();
        return request;
    }

    private void MessageSink(MessageLevel level, string message)
    {
        WriteMessage(level, message);
    }

    private ErrorRecord BuildConnectionErrorRecord(ConnectionResolutionException failure, DbaInstanceParameter instance)
    {
        // The PS source passed the caught ErrorRecord ($connectionError); its category was
        // NotSpecified so Stop-Function's -Category ConnectionError won the category vote
        // (the DbaBaseCmdlet truth table replicates that).
        Exception inner = failure.InnerException ?? failure;
        return new ErrorRecord(inner, "dbatools_Connect-DbaInstance", ErrorCategory.NotSpecified, instance);
    }

    /// <summary>
    /// The pinned begin block's Invoke-TEPPCacheUpdate (pinned 460-480). The pin re-creates the gather script with
    /// [ScriptBlock]::Create, so it runs in the process block's scope and reads $FullSmoName and $server from there;
    /// those are the two variables the registered gather scripts use, so they are defined in the script's own scope.
    /// The module registers its gather scripts from the dbatools-maintenance runspace (teppInsertTask), and a script
    /// block keeps its home runspace: invoked as it is, it runs there and does not see the two variables (measured on
    /// both editions, item evidence tepp-cross-runspace-20261112.txt). Rebinding the registered block's own parsed tree
    /// gives the same code bound to this runspace, with no text and no parse (watchman cde2e907, option 1; harness-edits.md
    /// "Connect-DbaInstance: the registered TEPP rebind, the :412 register entry and no cluster InstanceMulti1 (operator,
    /// 2026-11-12)", point 1). It is done only for blocks read from TabExpansionHost.TeppGatherScriptsFast.
    /// </summary>
    private void InvokeTeppCacheUpdate(ScriptBlock scriptBlock, string fullSmoName, Server server)
    {
        try
        {
            List<PSVariable> variables = new()
            {
                new PSVariable("FullSmoName", fullSmoName),
                new PSVariable("server", server)
            };
            ScriptBlock local = scriptBlock.Ast is ScriptBlockAst registeredAst ? registeredAst.GetScriptBlock() : scriptBlock;
            local.InvokeWithContext((IDictionary?)null, variables);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            // If the SQL Server version doesn't support the feature, we ignore it and silently continue
            // (the PS source matched $_.Exception.InnerException.InnerException; the compiled
            // invocation wraps differently, so the whole chain is checked for the same type).
            for (Exception? current = ex; current is not null; current = current.InnerException)
            {
                if (current.GetType().FullName == "Microsoft.SqlServer.Management.Sdk.Sfc.InvalidVersionEnumeratorException")
                {
                    return;
                }
            }

            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPVEYOR_BUILD_FOLDER")) || MessageHost.DeveloperMode)
            {
                // Pinned: Stop-Function -Message, without the argument. PowerShell refuses that call with a binding
                // error, which is reported, and the loop goes on with the next gather script.
                ParameterBindingException missingArgument = new("Missing an argument for parameter 'Message'. Specify a parameter of type 'System.String' and try again.");
                WriteError(new ErrorRecord(missingArgument, "MissingArgument,Stop-Function", ErrorCategory.InvalidArgument, null));
                return;
            }

            // PS: Write-Message -Level Warning -Message "Failed TEPP Caching: ..." -ErrorRecord $_ 3>$null
            // The 3>$null suppressed the warning display while it still reached the logs.
            WriteSuppressedWarning("Failed TEPP Caching: " + ExtractTeppScriptName(scriptBlock), ex);
        }
    }

    private static string ExtractTeppScriptName(ScriptBlock scriptBlock)
    {
        // PS: $scriptBlock.ToString() | Select-String '"(.*?)"' | ForEach-Object { $_.Matches[0].Groups[1].Value }
        // The first double-quoted string of the block, read from its AST in source order, between its quotes (watchman
        // cde2e907). Measured equal to the pinned text for all 28 registered gather scripts on both editions (item
        // evidence tepp-log-names-20261112.txt).
        Ast? first = null;
        foreach (Ast found in scriptBlock.Ast.FindAll(IsDoubleQuotedString, true))
        {
            if (first is null || found.Extent.StartOffset < first.Extent.StartOffset)
            {
                first = found;
            }
        }

        string text = first?.Extent.Text ?? string.Empty;
        return text.Length >= 2 ? text.Substring(1, text.Length - 2) : string.Empty;
    }

    private static bool IsDoubleQuotedString(Ast ast)
    {
        return (ast is StringConstantExpressionAst constant && constant.StringConstantType == StringConstantType.DoubleQuoted)
            || (ast is ExpandableStringExpressionAst expandable && expandable.StringConstantType == StringConstantType.DoubleQuoted);
    }

    private void WriteSuppressedWarning(string message, Exception exception)
    {
        // Write-Message ... 3>$null equivalent: the text reaches LogHost and the error log but
        // not the warning stream (the same mechanism StopFunction uses under EnableException).
        // The pinned call passes no -EnableException, so Write-Message's own default (off) applies and the
        // error record is only logged, never written to the error stream.
        MessageService.MessageRequest request = new()
        {
            Level                  = MessageLevel.Warning,
            Message                = message,
            FunctionName           = "Connect-DbaInstance",
            ModuleName             = "dbatools",
            Exception              = exception,
            EnableException        = false,
            SuppressWarningDisplay = true,
            File                   = MyInvocation.ScriptName,
            Line                   = MyInvocation.ScriptLineNumber
        };
        MessageService.Write(this, request);
    }
}
