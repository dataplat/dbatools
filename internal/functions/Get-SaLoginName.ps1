function Get-SaLoginName {
    <#
    .SYNOPSIS
    Gets the login matching the standard "sa" user

    .DESCRIPTION
    Gets the login matching the standard "sa" user, useful in case of renames

    .PARAMETER SqlInstance
    The SQL Server instance.

    .PARAMETER SqlCredential
    Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted).

    .EXAMPLE
    Get-SaLoginName -SqlInstance base\sql2016

    .NOTES
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [PSCredential]$SqlCredential
    )

    $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    $saname = ($server.logins | Where-Object { $_.id -eq 1 }).Name

    return $saname
}