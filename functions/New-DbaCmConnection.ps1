function New-DbaCmConnection {
    <#
    .SYNOPSIS
        Generates a connection object for use in remote computer management.

    .DESCRIPTION
        Generates a connection object for use in remote computer management.
        Those objects are used for the purpose of cim/wmi queries, caching which protocol worked, optimizing performance and minimizing authentication errors.

        New-DbaCmConnection will create a NEW object and overwrite any existing ones for the specified computer.
        Furthermore, information stored in the input beyond the computername will be discarded in favor of the new settings.

        Unless the connection cache has been disabled, all connections will automatically be registered in the cache, so no further action is necessary.
        The output is primarily for information purposes, however it may be used to pass objects and circumvent the cache with those.

        NOTE: Generally, this function need not be used, as a first connection to a computer using any connecting function such as "Get-DbaCmObject" will automatically register a new default connection for it.

        This function exists to be able to preconfigure connections.

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
        Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaCmConnection

    .EXAMPLE
        PS C:\> New-DbaCmConnection -ComputerName sql2014 -UseWindowsCredentials -OverrideExplicitCredential -DisabledConnectionTypes CimRM

        Returns a new configuration object for connecting to the computer sql2014.
        - The current user credentials are set as valid
        - The connection is configured to ignore explicit credentials (so all connections use the windows credentials)
        - The connections will not try using CIM over WinRM

        Unless caching is globally disabled, this is automatically stored in the connection cache and will be applied automatically.
        In that (the default) case, the output is for information purposes only and need not be used.

    .EXAMPLE
        PS C:\> Get-Content computers.txt | New-DbaCmConnection -Credential $cred -CimWinRMOptions $options -DisableBadCredentialCache -OverrideExplicitCredential

        Gathers a list of computers from a text file, then creates and registers connections for each of them, setting them to ...
        - use the credentials stored in $cred
        - use the options stored in $options when connecting using CIM over WinRM
        - not store credentials that are known to not work
        - to ignore explicitly specified credentials

        Essentially, this configures all connections to those computers to prefer failure with the specified credentials over using alternative credentials.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Credential')]
    param (
        [Parameter(ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Credential")]
        [PSCredential]
        $Credential,
        [Parameter(ParameterSetName = "Windows")]
        [switch]
        $UseWindowsCredentials,
        [switch]
        $OverrideExplicitCredential,
        [Sqlcollaborative.Dbatools.Connection.ManagementConnectionType]
        $DisabledConnectionTypes = 'None',
        [switch]
        $DisableBadCredentialCache,
        [switch]
        $DisableCimPersistence,
        [switch]
        $DisableCredentialAutoRegister,
        [switch]
        $EnableCredentialFailover,
        [Parameter(ParameterSetName = "Credential")]
        [switch]
        $WindowsCredentialsAreBad,
        [Microsoft.Management.Infrastructure.Options.WSManSessionOptions]
        $CimWinRMOptions,
        [Microsoft.Management.Infrastructure.Options.DComSessionOptions]
        $CimDCOMOptions,
        [switch]$EnableException
    )
    begin {
        Write-Message -Level InternalComment -Message "Starting execution"
        Write-Message -Level Verbose -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        $disable_cache = Get-DbatoolsConfigValue -Name 'ComputerManagement.Cache.Disable.All' -Fallback $false
    }
    process {
        foreach ($connectionObject in $ComputerName) {
            if ($Pscmdlet.ShouldProcess($($connectionObject.connection.computername), "Creating connection object")) {
                if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue }
                Write-Message -Level VeryVerbose -Message "Processing computer: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection

                $connection = New-Object -TypeName Sqlcollaborative.Dbatools.Connection.ManagementConnection -ArgumentList $connectionObject.Connection.ComputerName
                if (Test-Bound "Credential") { $connection.Credentials = $Credential }
                if (Test-Bound "UseWindowsCredentials") {
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