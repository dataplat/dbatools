function Connect-ConnstringInstance {
    <#
    .SYNOPSIS
        Internal function to establish smo connections using a connstring

    .DESCRIPTION
       Internal function to establish smo connections using a connstring

        Can interpret any of the following types of information:
        - String
        - Smo Server objects

    .PARAMETER SqlInstance
        The SQL Server instance to restore to.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER AzureUnsupported
        Throw if Azure is detected but not supported

    .PARAMETER MinimumVersion
       The minimum version that the calling command will support

    .PARAMETER StatementTimeout
        Sets the number of seconds a statement is given to run before failing with a timeout error.

    .EXAMPLE
        Connect-SqlInstance -SqlInstance sql2014

        Connect to the Server sql2014 with native credentials.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int]$StatementTimeout,
        [int]$MinimumVersion,
        [switch]$AzureUnsupported,
        [switch]$NonPooled
    )
    if ($SqlInstance.InputObject.GetType().Name -eq 'Server') {
        $SqlInstance.InputObject.Refresh()
        return $SqlInstance.InputObject
    } else {
        $boundparams = $PSBoundParameters
        [object[]]$connstringcmd = (Get-Command New-DbaConnectionString).Parameters.Keys
        [object[]]$connectcmd = (Get-Command Connect-ConnstringInstance).Parameters.Keys

        foreach ($key in $connectcmd) {
            if ($key -notin $connstringcmd -and $key -ne "SqlCredential") {
                $null = $boundparams.Remove($key)
            }
        }
        # Build connection string
        $connstring = New-DbaConnectionString @boundparams -ClientName "dbatools PowerShell module - dbatools.io"
        $sqlconn = New-Object System.Data.SqlClient.SqlConnection $connstring
        $serverconn = New-Object Microsoft.SqlServer.Management.Common.ServerConnection $sqlconn
        $null = $serverconn.Connect()
        New-Object Microsoft.SqlServer.Management.Smo.Server $serverconn
    }
}