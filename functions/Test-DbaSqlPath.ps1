#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Test-DbaSqlPath {
	<#
        .SYNOPSIS
            Tests if file or directory exists from the perspective of the SQL Server service account.
        
        .DESCRIPTION
            Uses master.dbo.xp_fileexist to determine if a file or directory exists.
        
        .PARAMETER SqlInstance
            The SQL Server you want to run the test on.
        
        .PARAMETER SqlCredential
 			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

			To connect as a different Windows user, run PowerShell as that user.
        
        .PARAMETER Path
            The Path to test. This can be a file or directory
        
        .PARAMETER Silent
            If this switch is enabled, the internal messaging functions will be silenced.
        
        .EXAMPLE
            Test-DbaSqlPath -SqlInstance sqlcluster -Path L:\MSAS12.MSSQLSERVER\OLAP
            
            Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using Windows credentials.
        
        .EXAMPLE
            $credential = Get-Credential
            Test-DbaSqlPath -SqlInstance sqlcluster -SqlCredential $credential -Path L:\MSAS12.MSSQLSERVER\OLAP
            
            Tests whether the service account running the "sqlcluster" SQL Server instance can access L:\MSAS12.MSSQLSERVER\OLAP. Logs into sqlcluster using SQL authentication.
        
        .OUTPUTS
            System.Boolean
        
        .NOTES
            Author: Chrissy LeMaire (@cl), netnerds.net
            Requires: Admin access to server (not SQL Services),
            Remoting must be enabled and accessible if $SqlInstance is not local
            
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0 

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
		[string]$Path,
		[System.Management.Automation.PSCredential]
		$SqlCredential,
		[switch]$Silent
	)
    
	try {
		$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	}
	catch {
		Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
		return
	}
    
	Write-Message -Level VeryVerbose -Message "Path check is $path."
	$sql = "EXEC master.dbo.xp_fileexist '$path'"
	try {
		Write-Message -Level Debug -Message "Executing: $sql."
		$fileexist = $server.ConnectionContext.ExecuteWithResults($sql)
	}
    
	catch {
		Stop-Function -Message "Failed to test the path $Path." -ErrorRecord $_ -Target $SqlInstance
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

