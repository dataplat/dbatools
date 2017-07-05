function Get-DbaDbMailHistory {
<#
	.SYNOPSIS
		Gets the history of mail sent from a SQL instance
	
	.DESCRIPTION
		Gets the history of mail sent from a SQL instance
	
	.PARAMETER SqlInstance
		The SQL Server instance, or instances.
	
	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

	.PARAMETER Since
	Datetime object used to narrow the results to the send request date
	
	.PARAMETER Silent 
		Use this switch to disable any kind of verbose messages
	
	.NOTES
		Tags: Logging
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0	
	
	.LINK
		https://dbatools.io/Get-DbaDbMailHistory
	
	.EXAMPLE
		Get-DbaDbMailHistory -SqlInstance sql01\sharepoint 
		
		Returns the entire dbmail log for the SQL Agent on sql01\sharepoint 

	
	.EXAMPLE
		$servers = "sql2014","sql2016", "sqlcluster\sharepoint"
		$servers | Get-DbaDbMailHistory
		
		Returns the all dbmail logs for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>	
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[DateTime]$Since,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category Connectiondbmail -dbmailRecord $_ -Target $instance -Continue
			}
			
			$sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName, 
					ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, 
					SERVERPROPERTY('ServerName') AS SqlInstance, 
					mailitem_id as MailItemId,
					profile_id as ProfileId,
					recipients as Recipients,
					copy_recipients as CopyRecipients,
					blind_copy_recipients as BlindCopyRecipients,
					subject as Subject,
					body as Body,
					body_format as BodyFormat,
					importance as Importance,
					sensitivity as Sensitivity,
					file_attachments as FileAttachments,
					attachment_encoding as AttachmentEncoding,
					query as Query,
					execute_query_database as ExecuteQueryDatabase,
					attach_query_result_as_file as AttachQueryResultAsFile,
					query_result_header as QueryResultHeader,
					query_result_width as QueryResultWidth,
					query_result_separator as QueryResultSeparator,
					exclude_query_output as ExcludeQueryOutput,
					append_query_error as AppendQueryError,
					send_request_date as SendRequestDate,
					send_request_user as SendRequestUser,
					sent_account_id as SentAccountId,
					sent_status as SentStatus,
					sent_date as SentDate,
					last_mod_date as LastModDate,
					last_mod_user as LastModUser
					from msdb.dbo.sysmail_allitems"
			
			if ($Since) {
				$sql += " WHERE send_request_date >= '$($Since.ToString("yyyy-MM-ddTHH:mm:ss"))'"
			}
			
			$server.Query($sql)# | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance
		}
	}
}