function Set-DbaCmConnection {
    <#
    .SYNOPSIS
        Configures remote computer connection settings for SQL Server host management.

    .DESCRIPTION
        Configures connection objects that dbatools uses to manage remote SQL Server host computers via CIM, WMI, and PowerShell remoting.
        This function creates new connection records for computers not yet cached, or modifies existing connection settings for previously contacted hosts.

        Use this to bulk-configure connection behavior, manage credential caching, or troubleshoot remote connection issues when dbatools functions need to access SQL Server host systems for tasks like service management, file operations, or system information gathering.

    .PARAMETER ComputerName
        Specifies the SQL Server host computer name to configure connection settings for. Accepts computer names, FQDNs, or IP addresses.
        Use this when you need to pre-configure how dbatools connects to specific SQL Server host machines for service management, file operations, or system administration tasks.

    .PARAMETER Credential
        The credential to register.

    .PARAMETER UseWindowsCredentials
        Confirms that Windows credentials of the current user should be used for remote connections to the target computer.
        Set this when you know the current user account has sufficient privileges on the remote SQL Server host and want to avoid credential prompts.

    .PARAMETER OverrideExplicitCredential
        Forces dbatools to use cached working credentials instead of explicitly provided credentials when available.
        Enable this when you want the connection system to automatically use known-good credentials rather than failing with explicitly provided but incorrect credentials.

    .PARAMETER OverrideConnectionPolicy
        Allows this connection to bypass global connection type restrictions configured in dbatools settings.
        Use this when you need to enable specific connection methods (CIM, WMI, PowerShell remoting) for individual computers that are normally disabled globally.

    .PARAMETER DisabledConnectionTypes
        Specifies which connection protocols to disable for this computer (CIM, WMI, PowerShell remoting, or combinations).
        Use this to block problematic connection methods on specific hosts while allowing others to work normally.

    .PARAMETER DisableBadCredentialCache
        Prevents dbatools from remembering credentials that fail authentication for this computer.
        Enable this when you're frequently changing credentials or troubleshooting authentication issues and don't want failed attempts cached.

    .PARAMETER DisableCimPersistence
        Forces dbatools to create new CIM sessions for each operation instead of reusing existing sessions.
        Use this when experiencing issues with persistent CIM connections or when you need fresh authentication for each operation.

    .PARAMETER DisableCredentialAutoRegister
        Prevents successful credentials from being automatically saved to the connection cache for future use.
        Enable this for security-sensitive environments where you don't want credentials stored in memory between operations.

    .PARAMETER EnableCredentialFailover
        Allows dbatools to automatically try previously successful credentials when the provided credentials fail.
        Use this to improve connection reliability by falling back to known working credentials when new ones don't authenticate properly.

    .PARAMETER WindowsCredentialsAreBad
        Marks the current user's Windows credentials as non-functional for this remote computer.
        Set this when you know Windows authentication won't work for the target host and want to prevent automatic attempts with current user credentials.

    .PARAMETER CimWinRMOptions
        Specifies advanced WinRM session options for CIM connections, such as authentication methods, timeouts, or proxy settings.
        Create this object using New-CimSessionOption and use when you need custom WinRM configuration for challenging network environments.

    .PARAMETER CimDCOMOptions
        Specifies advanced DCOM session options for CIM connections, including authentication, impersonation levels, or DCOM-specific settings.
        Create this object using New-CimSessionOption and use when connecting through firewalls or when WinRM isn't available.

    .PARAMETER AddBadCredential
        Adds specific credentials to the list of known non-working credentials for this computer.
        Use this to prevent dbatools from attempting credentials you know will fail, improving performance and avoiding account lockouts.

    .PARAMETER RemoveBadCredential
        Removes previously flagged credentials from the bad credential list for this computer.
        Use this when credentials that previously failed have been updated or permissions have been granted.

    .PARAMETER ClearBadCredential
        Removes all entries from the bad credential cache for this computer.
        Use this when troubleshooting authentication issues or after bulk credential updates that might affect previously failed credentials.

    .PARAMETER ClearCredential
        Removes any cached working credentials for this computer, forcing fresh authentication on next connection.
        Use this when credentials have changed or when you need to ensure the next connection uses newly provided credentials.

    .PARAMETER ResetCredential
        Performs a complete credential reset by clearing both working and failed credential caches and resetting Windows credential status.
        Use this for comprehensive credential troubleshooting or when starting fresh with connection authentication for a host.

    .PARAMETER ResetConnectionStatus
        Clears all connection protocol test results, marking CIM, WMI, and PowerShell remoting as untested for this computer.
        Use this to force dbatools to re-test connection methods after network changes, firewall updates, or service configuration changes.

    .PARAMETER ResetConfiguration
        Restores all connection behavior settings to system defaults, removing any computer-specific overrides.
        Use this to return a connection to standard behavior after testing custom settings or when troubleshooting connection issues.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: ComputerManagement, CIM
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaCmConnection

    .OUTPUTS
        Dataplat.Dbatools.Connection.ManagementConnection

        Returns the modified connection object after applying the specified configuration changes. The object represents the remote computer connection settings used by dbatools for CIM, WMI, and PowerShell remoting operations.

        Properties available on the returned object include:
        - ComputerName: The name of the SQL Server host computer for which connection settings were configured
        - IsConnected: Boolean indicating whether a successful connection to the remote computer has been established
        - CimRM: Current status of CIM (WinRM) connectivity (Unknown, Connected, Failed, Untested)
        - CimDCOM: Current status of CIM (DCOM) connectivity (Unknown, Connected, Failed, Untested)
        - Wmi: Current status of WMI connectivity (Unknown, Connected, Failed, Untested)
        - PowerShellRemoting: Current status of PowerShell remoting connectivity (Unknown, Connected, Failed, Untested)
        - Credentials: Currently cached credentials for this connection
        - UseWindowsCredentials: Boolean indicating whether Windows credentials of the current user are configured
        - DisabledConnectionTypes: Connection protocols disabled for this computer
        - OverrideExplicitCredential: Boolean indicating whether cached credentials override explicit parameters
        - OverrideConnectionPolicy: Boolean indicating whether global connection policies are bypassed

    .EXAMPLE
        PS C:\> Get-DbaCmConnection sql2014 | Set-DbaCmConnection -ClearBadCredential -UseWindowsCredentials

        Retrieves the already existing connection to sql2014, removes the list of not working credentials and configures it to default to the credentials of the logged on user.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection | Set-DbaCmConnection -RemoveBadCredential $cred

        Removes the credentials stored in $cred from all connections' list of "known to not work" credentials.
        Handy to update changes in privilege.

    .EXAMPLE
        PS C:\> Get-DbaCmConnection | Export-Clixml .\connections.xml
        PS C:\> Import-Clixml .\connections.xml | Set-DbaCmConnection -ResetConfiguration

        At first, the current cached connections are stored in an xml file. At a later time - possibly in the profile when starting the console again - those connections are imported again and applied again to the connection cache.

        In this example, the configuration settings will also be reset, since after re-import those will be set to explicit, rather than deriving them from the global settings.
        In many cases, using the default settings is desirable. For specific settings, use New-DbaCmConnection as part of the profile in order to explicitly configure a connection.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Credential')]
    param (
        [Parameter(ValueFromPipeline)]
        [Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Credential")]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Windows")]
        [switch]$UseWindowsCredentials,
        [switch]$OverrideExplicitCredential,
        [switch]$OverrideConnectionPolicy,
        [Dataplat.Dbatools.Connection.ManagementConnectionType]$DisabledConnectionTypes = 'None',
        [switch]$DisableBadCredentialCache,
        [switch]$DisableCimPersistence,
        [switch]$DisableCredentialAutoRegister,
        [switch]$EnableCredentialFailover,
        [Parameter(ParameterSetName = "Credential")]
        [switch]$WindowsCredentialsAreBad,
        [Microsoft.Management.Infrastructure.Options.WSManSessionOptions]$CimWinRMOptions,
        [Microsoft.Management.Infrastructure.Options.DComSessionOptions]$CimDCOMOptions,
        [System.Management.Automation.PSCredential[]]$AddBadCredential,
        [System.Management.Automation.PSCredential[]]$RemoveBadCredential,
        [switch]$ClearBadCredential,
        [switch]$ClearCredential,
        [switch]$ResetCredential,
        [switch]$ResetConnectionStatus,
        [switch]$ResetConfiguration,
        [switch]$EnableException
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting execution"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $disable_cache = Get-DbatoolsConfigValue -Name 'ComputerManagement.Cache.Disable.All' -Fallback $false
    }
    process {
        foreach ($connectionObject in $ComputerName) {
            if ($Pscmdlet.ShouldProcess($($connectionObject.Connection.ComputerName), "Setting Connection")) {
                if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue }
                Write-Message -Level VeryVerbose -Message "Processing computer: $($connectionObject.Connection.ComputerName)"

                $connection = $connectionObject.Connection

                if ($ResetConfiguration) {
                    Write-Message -Level Verbose -Message "Resetting the configuration to system default"

                    $connection.RestoreDefaultConfiguration()
                }

                if ($ResetConnectionStatus) {
                    Write-Message -Level Verbose -Message "Resetting the connection status"

                    $connection.CimRM = 'Unknown'
                    $connection.CimDCOM = 'Unknown'
                    $connection.Wmi = 'Unknown'
                    $connection.PowerShellRemoting = 'Unknown'

                    $connection.LastCimRM = New-Object System.DateTime(0)
                    $connection.LastCimDCOM = New-Object System.DateTime(0)
                    $connection.LastWmi = New-Object System.DateTime(0)
                    $connection.LastPowerShellRemoting = New-Object System.DateTime(0)
                }

                if ($ResetCredential) {
                    Write-Message -Level Verbose -Message "Resetting credentials"

                    $connection.KnownBadCredentials.Clear()
                    $connection.Credentials = $null
                    $connection.UseWindowsCredentials = $false
                    $connection.WindowsCredentialsAreBad = $false
                } else {
                    if ($ClearBadCredential) {
                        Write-Message -Level Verbose -Message "Clearing bad credentials"

                        $connection.KnownBadCredentials.Clear()
                        $connection.WindowsCredentialsAreBad = $false
                    }

                    if ($ClearCredential) {
                        Write-Message -Level Verbose -Message "Clearing credentials"

                        $connection.Credentials = $null
                        $connection.UseWindowsCredentials = $false
                    }
                }

                foreach ($badCred in $RemoveBadCredential) {
                    $connection.RemoveBadCredential($badCred)
                }

                foreach ($badCred in $AddBadCredential) {
                    $connection.AddBadCredential($badCred)
                }

                if (Test-Bound "Credential") { $connection.Credentials = $Credential }
                if ($UseWindowsCredentials) {
                    $connection.Credentials = $null
                    $connection.UseWindowsCredentials = $UseWindowsCredentials
                }
                if (Test-Bound "OverrideExplicitCredential") { $connection.OverrideExplicitCredential = $OverrideExplicitCredential }
                if (Test-Bound "DisabledConnectionTypes") { $connection.DisabledConnectionTypes = $DisabledConnectionTypes }
                if (Test-Bound "DisableBadCredentialCache") { $connection.DisableBadCredentialCache = $DisableBadCredentialCache }
                if (Test-Bound "DisableCimPersistence") { $connection.DisableCimPersistence = $DisableCimPersistence }
                if (Test-Bound "DisableCredentialAutoRegister") { $connection.DisableCredentialAutoRegister = $DisableCredentialAutoRegister }
                if (Test-Bound "EnableCredentialFailover") { $connection.DisableCredentialAutoRegister = $EnableCredentialFailover }
                if (Test-Bound "WindowsCredentialsAreBad") { $connection.WindowsCredentialsAreBad = $WindowsCredentialsAreBad }
                if (Test-Bound "CimWinRMOptions") {
                    $connection.CimWinRMOptions = $CimWinRMOptions
                } elseif ($null -eq $connection.CimWinRMOptions) {
                    $connection.CimWinRMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Default
                }
                if (Test-Bound "CimDCOMOptions") {
                    $connection.CimDCOMOptions = $CimDCOMOptions
                } elseif ($null -eq $connection.CimDCOMOptions) {
                    $connection.CimDCOMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Dcom
                }
                if (Test-Bound "OverrideConnectionPolicy") { $connection.OverrideConnectionPolicy = $OverrideConnectionPolicy }

                if (-not $disable_cache) {
                    Write-Message -Level Verbose -Message "Writing connection to cache"
                    [Dataplat.Dbatools.Connection.ConnectionHost]::Connections[$connectionObject.Connection.ComputerName] = $connection
                } else { Write-Message -Level Verbose -Message "Skipping writing to cache, since the cache has been disabled." }
                $connection
            }
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Stopping execution"
    }
}