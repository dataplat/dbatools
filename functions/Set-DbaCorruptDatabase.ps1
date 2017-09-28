function Set-DbaCorruptDatabase {
	<#
		.SYNOPSIS
      Utilizes the DBCC WRITEPAGE functionality to allow you to corrupt a specific database table for testing. 

		.DESCRIPTION
      In no uncertain terms, this is a non-production command. This will absolutely break your databases and that is its only purpose, please use it carefully. 
			This command can be used to verify your tests for corruption are successful, and to demo various scenarios for corrupting page data.
			
			This command will take an instance and database (and optionally a table) and set the database to single user mode, corrupt either the specified table or the first table it finds, and returns it to multi-user.

		.PARAMETER SqlInstance
			The SQL Server instance holding the databases to be removed.You must have sysadmin access and Server version must be SQL Server version 2000 or higher.

		.PARAMETER SqlCredential
			Allows you to login to Servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$cred = Get-Credential, this pass this $cred to the param. 
		
			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

		.PARAMETER Database
			The single database you would like to corrupt, this command does not support multiple databases (on purpose.)
      
    .PARAMETER Table
      The specific table you want corrupted, if you do not choose one, the first user table (alphabetically) will be chosen for corruption.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.PARAMETER Silent
			If this switch is enabled, the internal messaging functions will be silenced.

		.NOTES
			Tags: Corruption, Testing
			Author: Constantine Kokkinos (@mobileck https://constantinekokkinos.com)

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Set-DbaCorruptDatabase

		.EXAMPLE
			Set-DbaCorruptDatabase -SqlInstance sql2016 -Database containeddb

			Prompts for confirmation then selects the first table in database containeddb and corrupts it (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)
			
		.EXAMPLE
			Set-DbaCorruptDatabase -SqlInstance sql2016 -Database containeddb -Table Customers -Confirm:$false

			Does not prompt and immediately corrupts table customers in database containeddb on the sql2016 instance (by putting database into single user mode, writing to garbage to its first non-iam page, and returning it to multi-user.)
	#>
	[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter]$SqlInstance,
		[parameter(Mandatory = $false)]
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[parameter(Mandatory)]
    [object]$Database,
    [object]$Table,		
		[switch]$Silent
	)
	begin {				
		if (!$Database) {
			Stop-Function -Message "You must pass a database to be corrupted."
			return
    }    
    if ($SqlInstance.Count -gt 1) {
			Stop-Function -Message "You specified more than one SQL Server, this command can only corrupt one database at a time."
			return
    }
    if ($Database.Count -gt 1) {
			Stop-Function -Message "You specified more than one database, this command can only corrupt one database at a time."
			return
    }
	}
	process {
		if (Test-FunctionInterrupt) { return }		
			try {
				Write-Message -Level Verbose -Message "Connecting to $SqlInstance"
				$Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			if ($Server.VersionMajor -lt 9) {
				Stop-Function -Message "DBCC WRITEPAGE has been updated in SQL Server 2005 and later, this command does not support earlier verisons $($Server.VersionMajor)."
				return
			}
      $db = $Server.Databases | Where-Object Name -in $Database
      $Table = $db.Tables | Select-Object -First 1
      if (!$Table -or $Table.Count -ne 1) {
        Stop-Function -Message "There are no accessible tables in $Database."
        return
      }

      if ($Pscmdlet.ShouldProcess("$db on $Server", "CorruptDatabase")) {
        
        $ClusteredIndexID = 1
        $Offset = '4000'
        $Page = '0'
        $FileID = '1'
        $HexValue = '0x45'
        $NumberOfBytesToChange = '1'
        $BypassBufferPool = '1'          
        
        $DBCCIND = "DBCC IND (N'$DatabaseName',N'$($Table.Name)',$ClusteredIndexID)"          
        # I spit on dbnull btw        
        $Pages = ( $Server.Query($DBCCIND) |  Where-Object {-not($_.IAMFID.Equals([DBNull]::Value))} ) |  Select-Object -Property PageFID, PagePID -First 1                            
        $Page = $Pages.PagePID
        $FileID = $Pages.PageFID
        $DBCCWritePage = "DBCC WRITEPAGE (N'$Databasename', $FileID, $Page, $Offset, $NumberOfBytesToChange, $HexValue, $BypassBufferPool);"
				Write-Verbose "Settin single-user."
				$null = Stop-DbaProcess -SqlInstance $Server -Database $Database
        $null = Set-DbaDatabaseState -SqlServer $Server -Database $Database -SingleUser -Force
        try {
					Write-Verbose "Stopping processes."
					$null = Stop-DbaProcess -SqlInstance $Server -Database $Database
					Write-Verbose "Corrupting data."
					(Connect-SqlInstance -SqlInstance $Server -SqlCredential $SqlCredential).Databases[$Database].Query($DBCCWritePage)					
        }
        catch {
          Stop-Function -Message "Failed to write page." -Category WriteError -ErrorRecord $_ -Target $instance -Continue            
				}
				Write-Verbose "Setting multi-user."
				$Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
				$null = Set-DbaDatabaseState -SqlServer (Connect-SqlInstance -SqlInstance $Server -SqlCredential $SqlCredential) -Database $Database -MultiUser -Force
				
        [pscustomobject]@{
          ComputerName = $Server.NetName
          InstanceName = $Server.ServiceName
          SqlInstance = $Server.DomainInstanceName
          Database = $db.Name
          Table = $Table.Name
          Status = "Corrupted"
        }
      }
	  }
	end {
		if (Test-FunctionInterrupt) { return }
		<# any cleanup needed #>
	}
}