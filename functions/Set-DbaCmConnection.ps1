function Set-DbaCmConnection {
    <#
    .SYNOPSIS
        Configures a connection object for use in remote computer management.

    .DESCRIPTION
        Configures a connection object for use in remote computer management.
        This function will either create new records for computers that have no connection registered so far, or it will configure existing connections if already present.

        As such it can be handy in making bulk-edits on connections or manually adjusting some settings.

    .PARAMETER ComputerName
        The computer to build the connection object for.

    .PARAMETER Credential
        The credential to register.

    .PARAMETER UseWindowsCredentials
        Whether using the default windows credentials is legit.
        Not setting this will not exclude using windows credentials, but only not pre-confirm them as working.

    .PARAMETER OverrideExplicitCredential
        Setting this will enable the credential override.
        The override will cause the system to ignore explicitly specified credentials, so long as known, good credentials are available.

    .PARAMETER OverrideConnectionPolicy
        Setting this will configure the connection policy override.
        By default, global configurations enforce, which connection type is available at all and which is disabled.

    .PARAMETER DisabledConnectionTypes
        Explicitly disable connection types.
        These types will then not be used for connecting to the computer.

    .PARAMETER DisableBadCredentialCache
        Will prevent the caching of credentials if set to true.

    .PARAMETER DisableCimPersistence
        Will prevent Cim-Sessions to be reused.

    .PARAMETER DisableCredentialAutoRegister
        Will prevent working credentials from being automatically cached

    .PARAMETER EnableCredentialFailover
        Will enable automatic failing over to known to work credentials, when using bad credentials.
        By default, passing bad credentials will cause the Computer Management functions to interrupt with a warning (Or exception if in silent mode).

    .PARAMETER WindowsCredentialsAreBad
        Will prevent the windows credentials of the currently logged on user from being used for the remote connection.

    .PARAMETER CimWinRMOptions
        Specify a set of options to use when connecting to the target computer using CIM over WinRM.
        Use 'New-CimSessionOption' to create such an object.

    .PARAMETER CimDCOMOptions
        Specify a set of options to use when connecting to the target computer using CIM over DCOM.
        Use 'New-CimSessionOption' to create such an object.

    .PARAMETER AddBadCredential
        Adds credentials to the bad credential cache.
        These credentials will not be used when connecting to the target remote computer.

    .PARAMETER RemoveBadCredential
        Removes credentials from the bad credential cache.

    .PARAMETER ClearBadCredential
        Clears the cache of credentials that didn't worked.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ClearCredential
        Clears the cache of credentials that worked.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ResetCredential
        Resets all credential-related caches:
        - Clears bad credential cache
        - Removes last working credential
        - Un-Confirms the windows credentials as working
        - Un-Confirms the windows credentials as not working

        Automatically implies the parameters -ClearCredential and -ClearBadCredential. Using them together is redundant.
        Will be applied before adding entries to the credential cache.

    .PARAMETER ResetConnectionStatus
        Restores all connection status to default, as if no connection protocol had ever been tested.

    .PARAMETER ResetConfiguration
        Restores the configuration back to system default.
        Configuration elements are the basic behavior controlling settings, such as whether to cache bad credentials, etc.
        These can be configured globally using the dbatools configuration system and overridden locally on a per-connection basis.
        For a list of all available settings, use "Get-DbatoolsConfig -Module ComputerManagement".

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
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Credential")]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName = "Windows")]
        [switch]$UseWindowsCredentials,
        [switch]$OverrideExplicitCredential,
        [switch]$OverrideConnectionPolicy,
        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType]$DisabledConnectionTypes = 'None',
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
                if (Test-Bound "CimWinRMOptions") { $connection.CimWinRMOptions = $CimWinRMOptions }
                if (Test-Bound "CimDCOMOptions") { $connection.CimDCOMOptions = $CimDCOMOptions }
                if (Test-Bound "OverrideConnectionPolicy") { $connection.OverrideConnectionPolicy = $OverrideConnectionPolicy }

                if (-not $disable_cache) {
                    Write-Message -Level Verbose -Message "Writing connection to cache"
                    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::Connections[$connectionObject.Connection.ComputerName] = $connection
                } else { Write-Message -Level Verbose -Message "Skipping writing to cache, since the cache has been disabled." }
                $connection
            }
        }
    }
    end {
        Write-Message -Level InternalComment -Message "Stopping execution"
    }
}