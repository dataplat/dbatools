function Set-DbatoolsInsecureConnection {
    <#
    .SYNOPSIS
        Reverts SQL Server connection security defaults to disable encryption and trust all certificates

    .DESCRIPTION
        Microsoft changed the default connection settings in SQL Server client libraries to require encryption and validate certificates, which can break existing dbatools scripts and connections in development environments. This function reverts those security defaults by configuring dbatools to trust all server certificates and disable encryption requirements.

        The function sets two key dbatools configuration values: sql.connection.trustcert (true) and sql.connection.encrypt (false). By default, these settings persist across PowerShell sessions, but you can use -SessionOnly to apply them temporarily.

        This is particularly useful when working with development servers, self-signed certificates, or legacy environments where the new security defaults cause connection failures.

        You can read more here: https://dbatools.io/newdefaults

    .PARAMETER SessionOnly
        Applies the insecure connection settings only to the current PowerShell session instead of persisting them permanently.
        Use this when testing connection settings or when you need insecure connections temporarily without changing your permanent dbatools configuration.

    .PARAMETER Scope
        Specifies where to store the persistent connection settings when SessionOnly is not used. Defaults to UserDefault.
        UserDefault applies to the current user only, while SystemDefault applies to all users on the machine.

    .PARAMETER Register
        This parameter is deprecated and will be removed in a future release.
        The function now automatically handles registration of settings when SessionOnly is not specified.

    .OUTPUTS
        Dataplat.Dbatools.Configuration.Config

        Returns two configuration objects representing the settings that were modified:
        - sql.connection.trustcert (set to true)
        - sql.connection.encrypt (set to false)

        Each object contains properties describing the configuration setting:
        - Module: The module name ("sql")
        - Name: The configuration setting name (e.g., "connection.trustcert")
        - Value: The current value ($true or $false)
        - Description: Human-readable description of the configuration setting

    .LINK
        https://dbatools.io/Set-DbatoolsInsecureConnection
        https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/

    .EXAMPLE
        PS C:\> Set-DbatoolsInsecureConnection

        Sets the default connection settings to trust all server certificates and not require encrypted connections.

    .EXAMPLE
        PS C:\> Set-DbatoolsInsecureConnection -SessionOnly

        Sets the default connection settings to trust all server certificates and not require encrypted connections.

        Does not persist across sessions so the default will return if you close and reopen PowerShell.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [switch]$SessionOnly,
        [Dataplat.Dbatools.Configuration.ConfigScope]$Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault,
        [switch]$Register
    )
    process {
        if ($Register) {
            Write-Message -Level Warning -Message "The Register parameter is deprecated and will be removed in a future release."
        }
        # Set these defaults for all future sessions on this machine
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Passthru
        Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Passthru

        if (-not $SessionOnly) {
            Register-DbatoolsConfig -FullName sql.connection.trustcert -Scope $Scope
            Register-DbatoolsConfig -FullName sql.connection.encrypt -Scope $Scope
        }
    }
}