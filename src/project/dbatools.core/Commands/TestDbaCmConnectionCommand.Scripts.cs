#nullable enable

namespace Dataplat.Dbatools.Commands;

/// <summary>The embedded hop scripts for Test-DbaCmConnection (W3-107) - split from
/// the main class file per the repository 400-line limit (codex r1).</summary>
public sealed partial class TestDbaCmConnectionCommand
{
    // PS: the begin configuration region VERBATIM (comments preserved). The helper
    // functions the source also defines in begin are function-scope state the hop
    // cannot persist - they move into the process hop (see class doc). The config
    // snapshot rides the sentinel so later records see the begin-time value.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    #region Configuration Values
    $disable_cache = Get-DbatoolsConfigValue -Name "ComputerManagement.Cache.Disable.All" -Fallback $false
    #Variable marked as unused by PSScriptAnalyzer
    #$disable_badcredentialcache = Get-DbatoolsConfigValue -Name "ComputerManagement.Cache.Disable.BadCredentialList" -Fallback $false
    #endregion Configuration Values

    @{ __w3107State = @{ disable_cache = $disable_cache } }
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record, preceded by the sentinel restore and
    // the re-declared begin helpers (see class doc). Substitutions only: explicit
    // -FunctionName Test-DbaCmConnection on hop-frame Stop-Function/Write-Message
    // (W1-090) - the re-declared helpers contain neither.
    private const string ProcessScript = """
param($ComputerName, $Credential, $Type, $Force, $EnableException, $__state, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[]]$ComputerName, [PSCredential]$Credential, [Dataplat.Dbatools.Connection.ManagementConnectionType[]]$Type, $Force, $EnableException, $__state, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        $disable_cache = $__state.disable_cache

        #region Helper Functions
        function Test-ConnectionCimRM {
            [CmdletBinding()]
            param (
                [Dataplat.Dbatools.Parameter.DbaCmConnectionParameter]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = $ComputerName.Connection.GetCimRMInstance($Credential, "Win32_OperatingSystem", "root\cimv2")

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $false
                    }
                } else {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }

        function Test-ConnectionCimDCOM {
            [CmdletBinding()]
            param (
                [Dataplat.Dbatools.Parameter.DbaCmConnectionParameter]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = $ComputerName.Connection.GetCimDComInstance($Credential, "Win32_OperatingSystem", "root\cimv2")

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                if (($_.Exception.InnerException -eq 0x8007052e) -or ($_.Exception.InnerException -eq 0x80070005)) {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $false
                    }
                } else {
                    New-Object PSObject -Property @{
                        Success       = "Error"
                        Timestamp     = Get-Date
                        Authenticated = $true
                    }
                }
            }
        }

        function Test-ConnectionWmi {
            [CmdletBinding()]
            param (
                [string]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = Get-WmiObject -ComputerName $ComputerName -Credential $Credential -Class Win32_OperatingSystem -ErrorAction Stop
                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch [System.UnauthorizedAccessException] {
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $false
                }
            } catch {
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            }
        }

        function Test-ConnectionPowerShellRemoting {
            [CmdletBinding()]
            param (
                [string]
                $ComputerName,

                [System.Management.Automation.PSCredential]
                $Credential
            )

            try {
                $parameters = @{
                    ScriptBlock  = { Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop }
                    ComputerName = $ComputerName
                    ErrorAction  = 'Stop'
                }
                if ($Credential) { $parameters["Credential"] = $Credential }
                #Variable $os marked as unused by PSScriptAnalyzer replace with $null to catch output
                $null = Invoke-Command @parameters

                New-Object PSObject -Property @{
                    Success       = "Success"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            } catch {
                # Will always consider authenticated, since any call with credentials to a server that doesn't exist will also carry invalid credentials error.
                # There simply is no way to differentiate between actual authentication errors and server not reached
                New-Object PSObject -Property @{
                    Success       = "Error"
                    Timestamp     = Get-Date
                    Authenticated = $true
                }
            }
        }
        #endregion Helper Functions

        foreach ($ConnectionObject in $ComputerName) {
            if (-not $ConnectionObject.Success) { Stop-Function -Message "Failed to interpret input: $($ConnectionObject.Input)" -Category InvalidArgument -Target $ConnectionObject.Input -Continue -FunctionName Test-DbaCmConnection }

            $Computer = $ConnectionObject.Connection.ComputerName.ToLowerInvariant()
            Write-Message -Level VeryVerbose -Message "[$Computer] Testing management connection" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"

            #region Setup connection object
            $con = $ConnectionObject.Connection

            # Ensure CIM session options are initialized with the configured operation timeout
            if ($null -eq $con.CimWinRMOptions) {
                $con.CimWinRMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Default
            }
            if ($null -eq $con.CimDCOMOptions) {
                $con.CimDCOMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Dcom
            }
            #endregion Setup connection object

            #region Handle credentials
            #Variable marked as unused by PSScriptAnalyzer
            #$BadCredentialsFound = $false
            if ($con.DisableBadCredentialCache) { $con.KnownBadCredentials.Clear() }
            elseif ($con.IsBadCredential($Credential) -and (-not $Force)) {
                Stop-Function -Message "[$Computer] The credentials supplied are on the list of known bad credentials, skipping. Use -Force to override this." -Continue -Category InvalidArgument -Target $Computer -FunctionName Test-DbaCmConnection
            } elseif ($con.IsBadCredential($Credential) -and $Force) {
                $con.RemoveBadCredential($Credential)
            }
            #endregion Handle credentials

            #region Connectivity Tests
            :types foreach ($ConnectionType in $Type) {
                switch ($ConnectionType) {
                    #region CimRM
                    "CimRM" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using CIM over WinRM" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                        $res = Test-ConnectionCimRM -ComputerName $con -Credential $Credential
                        $con.LastCimRM = $res.Timestamp
                        $con.CimRM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] CIM over WinRM Results | Success: $($res.Success), Authentication: $($res.Authenticated)" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimRM

                    #region CimDCOM
                    "CimDCOM" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using CIM over DCOM." -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                        $res = Test-ConnectionCimDCOM -ComputerName $con -Credential $Credential
                        $con.LastCimDCOM = $res.Timestamp
                        $con.CimDCOM = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] CIM over DCOM Results | Success: $($res.Success), Authentication: $($res.Authenticated)" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests." -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion CimDCOM

                    #region Wmi
                    "Wmi" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using WMI." -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                        $res = Test-ConnectionWmi -ComputerName $Computer -Credential $Credential
                        $con.LastWmi = $res.Timestamp
                        $con.Wmi = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] WMI Results | Success: $($res.Success), Authentication: $($res.Authenticated)" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"

                        if (-not $res.Authenticated) {
                            Write-Message -Level Important -Message "[$Computer] The credentials supplied proved to be invalid. Skipping further tests" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                            $con.AddBadCredential($Credential)
                            break types
                        }
                    }
                    #endregion Wmi

                    #region PowerShell Remoting
                    "PowerShellRemoting" {
                        Write-Message -Level Verbose -Message "[$Computer] Testing management access using PowerShell Remoting." -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                        $res = Test-ConnectionPowerShellRemoting -ComputerName $Computer -Credential $Credential
                        $con.LastPowerShellRemoting = $res.Timestamp
                        $con.PowerShellRemoting = $res.Success
                        Write-Message -Level VeryVerbose -Message "[$Computer] PowerShell Remoting Results | Success: $($res.Success)" -FunctionName Test-DbaCmConnection -ModuleName "dbatools"
                    }
                    #endregion PowerShell Remoting
                }
            }
            #endregion Connectivity Tests

            if (-not $disable_cache) { [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$Computer] = $con }
            $con
        }
    }
} $ComputerName $Credential $Type $Force $EnableException $__state $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
