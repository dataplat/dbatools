function Set-DbatoolsInsecureConnection {
    <#
    .SYNOPSIS
        Sets the default connection settings to trust all server certificates and not require an encrypted connection.

    .DESCRIPTION
        Microsoft changed the default connection settings in the SQL Server connection libraries
        to require an encrypted connection and not trust all server certificates.

        This command reverts those defaults and sets the default connection settings to trust all server
        certificates and not require encrypted connections.

        You can read more here: https://dbatools.io/newdefaults

    .PARAMETER Register
        Registers the settings to persist across sessions so they'll be used even if you close and reopen PowerShell.

    .PARAMETER Scope
        The configuration scope it should be registered under. Defaults to UserDefault.

        Configuration scopes are the default locations configurations are being stored at.

    .LINK
        https://dbatools.io/Set-DbatoolsInsecureConnection
        https://blog.netnerds.net/2023/03/new-defaults-for-sql-server-connections-encryption-trust-certificate/

    .EXAMPLE
        PS C:\> Set-DbatoolsInsecureConnection

        Sets the default connection settings to trust all server certificates and not require encrypted connections.

    .EXAMPLE
        PS C:\> Set-DbatoolsInsecureConnection -Register

        Sets the default connection settings to trust all server certificates and not require encrypted connections.

        Registers the settings to persist across sessions so they'll be used even if you close and reopen PowerShell.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [switch]$Register,
        [Dataplat.Dbatools.Configuration.ConfigScope]$Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault
    )
    process {
        # Set these defaults for all future sessions on this machine
        Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Passthru
        Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Passthru

        if ($Register) {
            Register-DbatoolsConfig -FullName sql.connection.trustcert -Scope $Scope
            Register-DbatoolsConfig -FullName sql.connection.encrypt -Scope $Scope
        }
    }
}