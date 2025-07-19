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

    .PARAMETER SessionOnly
        Does not persist across sessions so the default will return if you close and reopen PowerShell.

    .PARAMETER Scope
        The configuration scope it should be registered under. Defaults to UserDefault.

        Configuration scopes are the default locations configurations are being stored at.

    .PARAMETER Register
        Deprecated.

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
        [Dataplat.Dbatools.Configuration.ConfigScope]$Scope,
        [switch]$Register
    )
    process {
        if (-not (Test-Bound 'Scope')) {
            $Scope = [Dataplat.Dbatools.Configuration.ConfigScope]::UserDefault
        }
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