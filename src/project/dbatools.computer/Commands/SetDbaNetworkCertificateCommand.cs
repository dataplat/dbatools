#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the network (TLS) certificate for a SQL Server instance - selecting a suitable
/// certificate automatically, applying a specific one by thumbprint or piped X509 object, or
/// unsetting the current one - then optionally restarts the engine. Port of
/// public/Set-DbaNetworkCertificate.ps1; surface pinned by
/// migration/baselines/Set-DbaNetworkCertificate.json.
///
/// This is a WHOLE-BODY module-scoped hop rather than the satellite's usual
/// RemoteExecutionService + NestedCommand.Invoke decomposition, and deliberately so: the command
/// drives THREE nested dbatools calls - the private Invoke-Command2 helper (the remote registry/
/// ACL scriptblock), Test-DbaNetworkCertificate and Restart-DbaService - and its unit test mocks
/// all three with -ModuleName dbatools. RemoteExecutionService is the compiled equivalent of
/// Invoke-Command2 and bypasses the PS function, so a decomposed port could not satisfy a
/// Mock Invoke-Command2 and would attempt real remoting under the unit leg. Running the verbatim
/// body inside the real dbatools script module resolves the private helper, binds the mocks, and
/// makes behavioral parity structural.
///
/// Cross-record analysis (source is an advanced function; the hop resets process locals per
/// record): $newThumbprint/$stepCounter/$oldThumbprint/$certTest/$detailedCertTest/$failedChecks/
/// $result/$notes/$message are all per-iteration (assigned before read on every path). $Thumbprint
/// is a parameter mutated by $Thumbprint = $Certificate.Thumbprint; its only cross-record read is
/// dominated by $Certificate, which the compiled cmdlet's own pipeline-parameter retention carries
/// across records identically to the source's function scope - so the derivation converges and
/// needs no sentinel. There is therefore no cross-record state to carry and no sentinel emission.
///
/// The Interrupted prologue is carried because the source's process block reads
/// Test-FunctionInterrupt. Mechanical edits to the verbatim body: $PScmdlet.ShouldProcess ->
/// $__realCmdlet.ShouldProcess, and -FunctionName Set-DbaNetworkCertificate on every hop-frame
/// Stop-Function/Write-Message plus -ModuleName "dbatools" on the Write-Message calls. Nothing else.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaNetworkCertificate", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class SetDbaNetworkCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 0)]
    [Alias("ComputerName")]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>An X509 certificate object to configure (typically piped from New-DbaComputerCertificate).</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public System.Security.Cryptography.X509Certificates.X509Certificate2? Certificate { get; set; }

    /// <summary>The thumbprint (40-char SHA-1) of an already-installed certificate to configure.</summary>
    [Parameter(ValueFromPipelineByPropertyName = true, Position = 3)]
    public string? Thumbprint { get; set; }

    /// <summary>Unsets the currently configured network certificate for the instance.</summary>
    [Parameter]
    public SwitchParameter UnsetCertificate { get; set; }

    /// <summary>Restarts the SQL Server engine after the change so it takes effect immediately.</summary>
    [Parameter]
    public SwitchParameter RestartService { get; set; }

    // EnableException is inherited from DbaBaseCmdlet (__AllParameterSets) - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // InvokeScopedStreaming, not the buffered InvokeScoped: this command emits one object per
        // instance inside the loop, and a later instance's Stop-Function -Continue throws under
        // -EnableException. Buffered would discard the output already produced for earlier instances
        // (DEF-001); streaming emits each as produced, matching the function world, and preserves a
        // top-level validation guard's warning through the flow-control unwind.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, Credential, Certificate, Thumbprint,
            UnsetCertificate.ToBool(), RestartService.ToBool(), EnableException.ToBool(),
            this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private static DbaInstanceParameter[]? DefaultSqlInstance()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }

    private const string ProcessScript = """
param($SqlInstance, $Credential, $Certificate, $Thumbprint, $UnsetCertificate, $RestartService, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$Credential, [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate, [string]$Thumbprint, $UnsetCertificate, $RestartService, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # The beginning of this scriptblock should be kept aligned to the ones in Get- and Set-DbaNetworkConfiguration.
    $scriptBlock = {
        # This scriptblock will be processed by Invoke-Command2 on the target machine.
        # We take an object as the first parameter which has to include the properties ComputerName, InstanceName and SqlFullName,
        # so normally a DbaInstanceParameter.
        $instance = $args[0]
        # In addition to Get-DbaNetworkConfiguration we need the thumbprint of the certificate we want to configure.
        $thumbprint = $args[1]
        $verbose = @()
        $exception = $null

        try {
            $verbose += "Starting initialization of WMI object"

            # As we go remote, ensure the assembly is loaded
            [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
            $wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
            $result = $wmi.Initialize()

            $verbose += "Initialization of WMI object finished with $result"

            $wmiService = $wmi.Services | Where-Object { $_.DisplayName -eq "SQL Server ($($instance.InstanceName))" }
            $regRoot = ($wmiService.AdvancedProperties | Where-Object Name -eq REGROOT).Value
            $verbose += "regRoot = '$regRoot'"
            if ([System.String]::IsNullOrEmpty($regRoot)) {
                $regRoot = $wmiService.AdvancedProperties | Where-Object { $_ -match 'REGROOT' }
                $verbose += "regRoot = '$regRoot'"
                if (![System.String]::IsNullOrEmpty($regRoot)) {
                    $regRoot = ($regRoot -Split 'Value\=')[1]
                    $verbose += "regRoot = '$regRoot'"
                } else {
                    # This is just for safty, as we just used Get-DbaNetworkConfiguration successfully
                    throw "Can't find regRoot"
                }
            }
            $regPath = "Registry::HKEY_LOCAL_MACHINE\$regRoot\MSSQLServer\SuperSocketNetLib"

            if ($thumbprint) {
                $verbose += "Certificate thumbprint to set: $thumbprint"

                $cert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop | Where-Object { $_.Thumbprint -eq $thumbprint }
                $keyPath = $env:ProgramData + "\Microsoft\Crypto\RSA\MachineKeys\"
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    $keyName = $cert.PrivateKey.Key.UniqueName
                } else {
                    $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
                }
                $keyFullPath = $keyPath + $keyName
                if (-not (Test-Path $keyFullPath -Type Leaf)) {
                    throw "Can't find private key path"
                }

                # Grant permissions to the Service SID
                $sqlSSID = "NT SERVICE\MSSQLSERVER"
                if ($instance.InstanceName -ne "MSSQLSERVER") {
                    $sqlSSID = "NT SERVICE\MSSQL$" + $instance.InstanceName
                }
                $permission = $sqlSSID, "Read", "Allow"
                $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission
                try {
                    $acl = Get-Acl -Path $keyFullPath -ErrorAction Stop
                    $null = $acl.AddAccessRule($accessRule)
                    Set-Acl -Path $keyFullPath -AclObject $acl -ErrorAction Stop
                } catch {
                    throw "Failed to set read permissions on certificate private key: $_"
                }

                Set-ItemProperty -Path $regPath -Name Certificate -Value $thumbprint.ToLowerInvariant() # to make it compat with SQL config
            } else {
                $verbose += "No certificate thumbprint provided, unsetting certificate configuration"

                Set-ItemProperty -Path $regPath -Name Certificate -Value $null
            }
        } catch {
            $exception = $_
        }

        [PSCustomObject]@{
            Verbose        = $verbose
            Exception      = $exception
            ServiceAccount = $wmiService.ServiceAccount
        }
    }

    # Registry access

    if (Test-FunctionInterrupt) { return }

    if ($UnsetCertificate -and ($Thumbprint -or $Certificate)) {
        Stop-Function -Message "-UnsetCertificate cannot be used with -Thumbprint or -Certificate." -FunctionName Set-DbaNetworkCertificate
        return
    }

    if ($Thumbprint -and $Thumbprint -notmatch '^[0-9A-Fa-f]{40}$') {
        Stop-Function -Message "The thumbprint must be a 40-character hexadecimal string (no spaces)." -FunctionName Set-DbaNetworkCertificate
        return
    }

    if ($Certificate) {
        Write-Message -Level Verbose -Message "Getting thumbprint" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
        $Thumbprint = $Certificate.Thumbprint
    }

    foreach ($instance in $SqlInstance) {
        $newThumbprint = $null
        $stepCounter = 0
        Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Testing certificate configuration for $instance"
        Write-Message -Level Verbose -Message "Processing $instance" -Target $instance -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
        # Using Test-DbaNetworkCertificate without certificate will use Get-DbaNetworkConfiguration to get all the information we need.
        # The commands also tests for elevation requirements and connectivity so we don't have to here.
        try {
            $splatTest = @{
                SqlInstance     = $instance
                Credential      = $Credential
                EnableException = $true
            }
            $certTest = Test-DbaNetworkCertificate @splatTest
            $oldThumbprint = $certTest.ConfiguredCertificateThumbprint
        } catch {
            Stop-Function -Message "Failed to use Test-DbaNetworkCertificate to get information for $instance" -Target $instance -ErrorRecord $_ -Continue -FunctionName Set-DbaNetworkCertificate
        }

        if ($UnsetCertificate) {
            if (-not $certTest.ConfiguredCertificateThumbprint) {
                Write-Message -Level Verbose -Message "There is no certificate configured for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                [PSCustomObject]@{
                    ComputerName          = $certTest.ComputerName
                    InstanceName          = $certTest.InstanceName
                    SqlInstance           = $certTest.SqlInstance
                    ServiceAccount        = $null
                    CertificateThumbprint = $null
                    Notes                 = 'No changes needed'
                }
                continue
            } else {
                Write-Message -Level Verbose -Message "Certificate $oldThumbprint will be unset for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                $newThumbprint = $null
            }
        } elseif ($Thumbprint) {
            if ($Thumbprint -eq $oldThumbprint -and $certTest.ConfiguredCertificateValid) {
                Write-Message -Level Verbose -Message "Certificate $oldThumbprint was already configured for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                [PSCustomObject]@{
                    ComputerName          = $certTest.ComputerName
                    InstanceName          = $certTest.InstanceName
                    SqlInstance           = $certTest.SqlInstance
                    ServiceAccount        = $null
                    CertificateThumbprint = $oldThumbprint
                    Notes                 = 'No changes needed'
                }
                continue
            } elseif ($Thumbprint -in $certTest.SuitableCertificates.Thumbprint) {
                Write-Message -Level Verbose -Message "Certificate $Thumbprint is suitable for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                $newThumbprint = $Thumbprint
            } else {
                Write-Message -Level Verbose -Message "Validating certificate $Thumbprint for $instance using Test-DbaNetworkCertificate" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                try {
                    $splatTest = @{
                        SqlInstance     = $instance
                        Credential      = $Credential
                        Thumbprint      = $Thumbprint
                        EnableException = $true
                    }
                    $detailedCertTest = Test-DbaNetworkCertificate @splatTest
                } catch {
                    Stop-Function -Message "Failed to validate certificate $Thumbprint for $instance" -Target $instance -ErrorRecord $_ -Continue -FunctionName Set-DbaNetworkCertificate
                }

                $failedChecks = @()
                if (-not $detailedCertTest.CertificateFound) { $failedChecks += "CertificateNotFound" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.KeyUsagesValid) { $failedChecks += "KeyUsagesInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.DnsNamesValid) { $failedChecks += "DnsNamesInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.PrivateKeyValid) { $failedChecks += "PrivateKeyInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.PublicKeyValid) { $failedChecks += "PublicKeyInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.SignatureAlgorithmValid) { $failedChecks += "SignatureAlgorithmInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.EnhancedKeyUsageValid) { $failedChecks += "EnhancedKeyUsageInvalid" }
                if ($detailedCertTest.CertificateFound -and -not $detailedCertTest.ValidityPeriodOk) { $failedChecks += "ValidityPeriodExpiredOrInsufficient" }
                Stop-Function -Message "Certificate $Thumbprint is not suitable for SQL Server network encryption on $instance. Failed checks: $($failedChecks -join ', ')." -Target $instance -Continue -FunctionName Set-DbaNetworkCertificate
            }
        } else {
            if ($certTest.ConfiguredCertificateValid) {
                Write-Message -Level Verbose -Message "Certificate $oldThumbprint was already configured for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                [PSCustomObject]@{
                    ComputerName          = $certTest.ComputerName
                    InstanceName          = $certTest.InstanceName
                    SqlInstance           = $certTest.SqlInstance
                    ServiceAccount        = $null
                    CertificateThumbprint = $oldThumbprint
                    Notes                 = 'No changes needed'
                }
                continue
            } elseif ($certTest.SuitableCertificateAvailable -and $certTest.SuitableCertificateCount -eq 1) {
                $newThumbprint = $certTest.SuitableCertificates.Thumbprint
                Write-Message -Level Verbose -Message "Certificate $newThumbprint was selected for $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
            } elseif ($certTest.SuitableCertificateAvailable) {
                Stop-Function -Message "More than one suitable certificate found on $instance. Please use -Thumbprint." -Target $instance -Continue -FunctionName Set-DbaNetworkCertificate
            } else {
                Stop-Function -Message "No suitable certificate found on $instance. Please use New-DbaComputerCertificate to create one." -Target $instance -Continue -FunctionName Set-DbaNetworkCertificate
            }
        }

        if ($UnsetCertificate) {
            $message = "Unsetting certificate $oldThumbprint"
        } else {
            $message = "Configuring certificate $newThumbprint"
        }
        if ($__realCmdlet.ShouldProcess($instance, $message)) {
            Write-ProgressHelper -StepNumber ($stepCounter++) -Message "$message for $instance"
            $result = Invoke-Command2 -ScriptBlock $scriptBlock -ArgumentList $instance, $newThumbprint -ComputerName $($certTest.ComputerName) -Credential $Credential -ErrorAction Stop
            foreach ($verbose in $result.Verbose) {
                Write-Message -Level Verbose -Message $verbose -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
            }
            if ($result.Exception) {
                # The new code pattern for WMI calls is used where all exceptions are catched and return as part of an object.
                Write-Message -Level Verbose -Message "Execution against $($certTest.ComputerName) failed with: $($result.Exception)" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                if ($UnsetCertificate) {
                    $message = "Failed to unset certificate $oldThumbprint for instance $instance."
                } else {
                    $message = "Failed to configure certificate $newThumbprint for instance $instance."
                }
                Stop-Function -Message $message -Target $instance -ErrorRecord $result.Exception -Continue -FunctionName Set-DbaNetworkCertificate
            }

            $notes = $null
            if ($RestartService) {
                Write-ProgressHelper -StepNumber ($stepCounter++) -Message "Restarting SQL Server service for $instance"
                try {
                    $splatRestartService = @{
                        SqlInstance     = $instance
                        Type            = "Engine"
                        Force           = $true
                        EnableException = $true
                    }
                    if ($Credential) {
                        $splatRestartService.Credential = $Credential
                    }
                    $null = Restart-DbaService @splatRestartService
                } catch {
                    $notes = "Failed to restart service"
                    Write-Message -Level Warning -Message "$notes for instance $instance." -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
                }
            } else {
                if ($UnsetCertificate) {
                    $notes = "Certificate removal will not take effect until SQL Server service is restarted"
                } else {
                    $notes = "New certificate will not take effect until SQL Server service is restarted"
                }
                Write-Message -Level Warning -Message "$notes for instance $instance" -FunctionName Set-DbaNetworkCertificate -ModuleName "dbatools"
            }

            [PSCustomObject]@{
                ComputerName          = $certTest.ComputerName
                InstanceName          = $certTest.InstanceName
                SqlInstance           = $certTest.SqlInstance
                ServiceAccount        = $result.ServiceAccount
                CertificateThumbprint = $newThumbprint
                Notes                 = $notes
            }
        }
    }
} $SqlInstance $Credential $Certificate $Thumbprint $UnsetCertificate $RestartService $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
