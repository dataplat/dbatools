function New-DbaCredential {
<#
.SYNOPSIS
Creates a new SQL Server credential

.DESCRIPTION
Creates a new credential
	
.PARAMETER SqlInstance
The target SQL Server(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER Name
The Credential name

.PARAMETER CredentialIdentity
The Credential Identity
	
.PARAMETER Password
Secure string used to authenticate the Credential Identity

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: Certificate

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.EXAMPLE
New-DbaCredential -SqlInstance Server1

You will be prompted to securely enter your password, then a credential will be created in the master database on server1 if it does not exist.

.EXAMPLE
New-DbaCredential -SqlInstance Server1 -Database db1 -Confirm:$false

Suppresses all prompts to install but prompts to securely enter your password and creates a credential in the 'db1' database


#>
	[CmdletBinding(SupportsShouldProcess = $true)] #, ConfirmImpact = "High"
	param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[object[]]$Name = $CredentialIdentity,
		[parameter(Mandatory)]
		[object[]]$CredentialIdentity,
		[Security.SecureString]$Password,
		[switch]$Silent
	)
	
	process {
		if (!$Password) {
			Read-Host -AsSecureString -Prompt "Enter the credential password"
		}
		
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			foreach ($cred in $CredentialIdentity) {
				$currentcred = $server.Credentials[$name]
				
				if ($currentcred) {
					if ($force) {
						Write-Message -Level Verbose -Message "Dropping credential $name"
						$currentcred.Drop()
					}
					else {
						Stop-Function -Message "Credential exists and Force was not specified" -Target $name -Continue
					}
				}
				
				
				if ($Pscmdlet.ShouldProcess($SqlInstance, "Creating credential for database '$cred' on $instance")) {
					try {
						$credential = New-Object Microsoft.SqlServer.Management.Smo.Credential -ArgumentList $server, $name
						$credential.Create($CredentialIdentity, $Password)
						
						Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name ComputerName -value $server.NetName
						Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
						Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
						Add-Member -Force -InputObject $credential -MemberType NoteProperty -Name Database -value $smodb
						$credential
						#Select-DefaultView -InputObject $credential -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
					}
					catch {
						Stop-Function -Message "Failed to create credential in $cred on $instance. Exception: $($_.Exception.InnerException)" -Target $credential -InnerErrorRecord $_ -Continue
					}
				}
			}
		}
	}
}