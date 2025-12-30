function New-DbaCmConnection {
    <#
    .SYNOPSIS
        Creates and configures connection objects for remote computer management using CIM/WMI protocols.

    .DESCRIPTION
        Creates connection objects that optimize remote computer management for SQL Server environments using CIM and WMI protocols.
        These objects cache successful authentication methods and connection protocols, reducing authentication errors and improving performance when connecting to multiple SQL Server instances across different servers.

        The function pre-configures connection settings including credentials, preferred protocols (CIM over WinRM or DCOM), and failover behavior.
        This eliminates the need to repeatedly authenticate and negotiate protocols when running dbatools commands against remote SQL Server instances.

        New-DbaCmConnection creates a new connection object and overwrites any existing cached connection for the specified computer.
        All connection information beyond the computer name gets replaced with the new settings you specify.

        Unless connection caching has been disabled globally, all connections are automatically stored in the connection cache for reuse.
        The returned object is primarily informational, though it can be used to bypass the cache if needed.

        Note: This function is typically optional since dbatools commands like Get-DbaCmObject automatically create default connections when first connecting to a computer.
        Use this function when you need to pre-configure specific authentication or protocol settings before running other dbatools commands.

    .PARAMETER ComputerName
        Specifies the target computer name or IP address where SQL Server instances are running.
        Use this to pre-configure connection settings before running other dbatools commands against remote SQL Server hosts.
        Accepts pipeline input for bulk configuration of multiple servers.

    .PARAMETER Credential
        The credential to register.

    .PARAMETER UseWindowsCredentials
        Confirms that the current Windows user credentials are valid for connecting to the target computer.
        Use this when your current domain account has administrative rights on the SQL Server host.
        Pre-validates these credentials to avoid authentication delays during subsequent dbatools operations.

    .PARAMETER OverrideExplicitCredential
        Forces the connection to use cached working credentials instead of any explicitly provided credentials.
        Use this when you want to ensure consistent authentication across multiple dbatools commands.
        Prevents authentication failures when mixed credentials are accidentally specified in scripts.

    .PARAMETER DisabledConnectionTypes
        Specifies which connection protocols to disable when connecting to the remote computer.
        Use this to force specific connection methods when certain protocols are blocked by network policies.
        Common values include 'CimRM' to disable CIM over WinRM or 'CimDCOM' to disable DCOM connections.

    .PARAMETER DisableBadCredentialCache
        Prevents failed credentials from being stored in the credential cache.
        Use this in environments where credentials change frequently or when testing different authentication methods.
        Helps avoid repeated authentication attempts with known bad credentials.

    .PARAMETER DisableCimPersistence
        Forces creation of new CIM sessions for each connection instead of reusing existing sessions.
        Use this when troubleshooting connection issues or when working with servers that have session limits.
        May impact performance but ensures fresh connections for each dbatools operation.

    .PARAMETER DisableCredentialAutoRegister
        Prevents successful credentials from being automatically stored in the connection cache.
        Use this for one-time operations where you don't want credentials persisted for future use.
        Useful in high-security environments where credential caching is not permitted.

    .PARAMETER EnableCredentialFailover
        Automatically switches to cached working credentials when the initially provided credentials fail.
        Use this to ensure dbatools operations continue even if incorrect credentials are accidentally specified.
        Prevents script interruptions due to authentication failures when multiple credential sets are available.

    .PARAMETER WindowsCredentialsAreBad
        Explicitly marks the current Windows user credentials as invalid for this computer connection.
        Use this when your domain account lacks privileges on the target SQL Server host.
        Forces the use of alternative credentials and prevents authentication attempts with insufficient privileges.

    .PARAMETER CimWinRMOptions
        Configures advanced WinRM connection settings for CIM sessions to the target computer.
        Use this to specify custom ports, authentication methods, or SSL settings required by your network configuration.
        Create the options object using New-CimSessionOption with specific timeout, encryption, or proxy settings.

    .PARAMETER CimDCOMOptions
        Configures advanced DCOM connection settings for legacy CIM sessions to the target computer.
        Use this when connecting to older Windows servers or when WinRM is not available.
        Create the options object using New-CimSessionOption with DCOM-specific authentication and timeout settings.

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

    .OUTPUTS
        Dataplat.Dbatools.Connection.ManagementConnection

        Returns one management connection object per computer name provided. The connection object caches authentication credentials and CIM/WMI session settings for reuse across multiple dbatools commands.

        Unless connection caching is disabled globally (via dbatools configuration), the returned object is automatically stored in the connection cache and used transparently for subsequent operations. The returned object itself is primarily informational but can be used to verify connection settings or to bypass the cache if needed.

        Key properties include:
        - ComputerName: The target computer name for the connection
        - Credentials: The PSCredential object for authentication, or null if using Windows credentials
        - UseWindowsCredentials: Boolean indicating if current Windows credentials are used
        - OverrideExplicitCredential: Boolean forcing use of cached credentials instead of explicit ones
        - DisabledConnectionTypes: ManagementConnectionType flags specifying which protocols to disable (CimRM, CimDCOM, etc.)
        - DisableBadCredentialCache: Boolean preventing storage of failed credentials
        - DisableCimPersistence: Boolean forcing new CIM sessions instead of reusing existing ones
        - DisableCredentialAutoRegister: Boolean preventing auto-storage of successful credentials
        - WindowsCredentialsAreBad: Boolean marking Windows credentials as invalid for this connection
        - CimWinRMOptions: WSManSessionOptions for configuring CIM over WinRM protocol settings
        - CimDCOMOptions: DComSessionOptions for configuring DCOM protocol settings

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
        [Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[]]
        $ComputerName = $env:COMPUTERNAME,
        [Parameter(ParameterSetName = "Credential")]
        [PSCredential]
        $Credential,
        [Parameter(ParameterSetName = "Windows")]
        [switch]
        $UseWindowsCredentials,
        [switch]
        $OverrideExplicitCredential,
        [Dataplat.Dbatools.Connection.ManagementConnectionType]
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

                $connection = New-Object -TypeName Dataplat.Dbatools.Connection.ManagementConnection -ArgumentList $connectionObject.Connection.ComputerName
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
                if (Test-Bound "CimWinRMOptions") {
                    $connection.CimWinRMOptions = $CimWinRMOptions
                } else {
                    $connection.CimWinRMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Default
                }
                if (Test-Bound "CimDCOMOptions") {
                    $connection.CimDCOMOptions = $CimDCOMOptions
                } else {
                    $connection.CimDCOMOptions = New-DbaCimSessionOptionWithTimeout -Protocol Dcom
                }

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