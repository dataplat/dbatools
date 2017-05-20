#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#

Function Test-DbaSqlPath {
<#
    .SYNOPSIS
        Tests if file or directory exists from the perspective of the SQL Server service account
    
    .DESCRIPTION
        Uses master.dbo.xp_fileexist to determine if a file or directory exists
    
    .PARAMETER SqlInstance
        The SQL Server you want to run the test on.
    
    .PARAMETER Path
        The Path to tests. Can be a file or directory.
    
    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        
        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
        
        Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows
        credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
    .EXAMPLE
        Test-DbaSqlPath -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP
        
        Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials.
    
    .EXAMPLE
        $credential = Get-Credential
        Test-DbaSqlPath -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP
        
        Tests whether the service account running the "sqlcluster" SQL Server isntance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication.
    
    .OUTPUTS
        System.Boolean
    
    .NOTES
        Author: Chrissy LeMaire (@cl), netnerds.net
        Requires: Admin access to server (not SQL Services),
        Remoting must be enabled and accessible if $SqlInstance is not local
        
        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        
        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.
        
        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.
        
        You should have received a copy of the GNU General Public License
        along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
    .LINK
        https://dbatools.io/Test-DbaSqlPath
#>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]
        $SqlInstance,
        
        [Parameter(Mandatory = $true)]
        [string]
        $Path,
        
        [System.Management.Automation.PSCredential]
        $SqlCredential,
        
        [switch]
        $Silent
    )
    
    try {
        $server = Connect-SqlServer -SqlServer $SqlInstance -SqlCredential $SqlCredential
    }
    catch {
        Stop-Function -Message "Failed to connect to $SqlInstance" -Silent $Silent -ErrorRecord $_
        return
    }
    
    Write-Message -Level VeryVerbose -Message "Path check is $path"
    $sql = "EXEC master.dbo.xp_fileexist '$path'"
    try {
        Write-Message -Level Debug -Message "Executing: $sql"
        $fileexist = $server.ConnectionContext.ExecuteWithResults($sql)
    }
    
    catch {
        Stop-Function -Message "Failed to test the path $Path" -ErrorRecord $_ -Target $SqlInstance
        return
    }
    if ($fileexist.tables.rows[0] -eq $true -or $fileexist.tables.rows[1] -eq $true) {
        return $true
    }
    else {
        return $false
    }
    
    Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Test-SqlPath
}

