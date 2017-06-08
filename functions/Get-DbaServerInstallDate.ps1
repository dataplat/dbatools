function Get-DbaServerInstallDate
{
<#
.SYNOPSIS
Returns the install date of SqlServer and Windows Server, depending on what is passed. 
	
.DESCRIPTION
By default, this command returns for each SQL Server instance passed in:
SQL Instance install date, formatted as a string
Hosting Windows server install date, formatted as a string
	
.PARAMETER SqlServer
The SQL Server that you're connecting to.

.PARAMETER SqlCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER WindowsCredential
Credential object used to connect to the SQL Server as a different user

.PARAMETER SqlOnly
Excludes the Windows server information

.PARAMETER WindowsOnly
Excludes the SQL server information

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES
Tags: CIM 
Original Author: Mitchell Hamann (@SirCaptainMitch), mitchellhamann.com
	
Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaInstallDate

.EXAMPLE
Get-DbaInstallDate -SqlServer SqlBox1\Instance2

Returns an object with SQL Server Install date as a string and the Windows install date as string. 

.EXAMPLE
Get-DbaInstallDate -SqlServer winserver\sqlexpress, sql2016

Returns an object with SQL Server Install date as a string and the Windows install date as a string for both SQLInstances that are passed to the cmdlet.  
	
.EXAMPLE   
Get-DbaInstallDate -SqlServer sqlserver2014a, sql2016 -SqlOnly

Returns an object with only the SQL Server Install date as a string. 

.EXAMPLE   
Get-DbaInstallDate -SqlServer sqlserver2014a, sql2016 -WindowsOnly

Returns an object with only the Windows Install date as a string. 

.EXAMPLE   
Get-SqlRegisteredServerName -SqlServer sql2014 | Get-DbaInstallDate

Returns an object with SQL Server Install date as a string and the Windows install date as string for every server listed in the Central Management Server on sql2014
	
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer", "ComputerName")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential] 
		[System.Management.Automation.CredentialAttribute()]$SqlCredential,
		[PSCredential] 
		[System.Management.Automation.CredentialAttribute()]$Credential,
		[parameter(ParameterSetName = "Sql")]
		[Switch]$SqlOnly,
		[parameter(ParameterSetName = "Windows")]
		[Switch]$WindowsOnly,		
		[switch]$Silent
	)
	
	PROCESS
	{
		foreach ($instance in $SqlServer)
		{
			if ($instance.Gettype().FullName -eq [System.Management.Automation.PSCustomObject] )
			{
				$servername = $instance.SqlInstance
			}
			elseif ($instance.Gettype().FullName -eq [Microsoft.SqlServer.Management.Smo.Server])
			{
				$servername = $instance.NetName
			}
			else
			{
				$servername = $instance
			}
						
			if ($WindowsOnly -ne $true)
			{ 				
				try 
				{
					Write-Message -Level Verbose -Message "Connecting to $instance"
                    if ($SqlCredential)
                    { 
						$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
                    } else 
                    {
						$server = Connect-SqlInstance -SqlInstance $servername
                    }					
				}
				catch 
				{
					Stop-Function -Message "Failed to connect to: $instance" -Continue -Target $instance -InnerErrorRecord $_
				}

				if ( $server.VersionMajor -ge 9 )
				{ 
					Write-Message -Level Verbose -Message "Getting Install Date for: $instance" 
					$sql = "SELECT create_date FROM sys.server_principals WHERE sid = 0x010100000000000512000000"
					[DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).create_date

				} else { 
					Write-Message -Level Verbose -Message "Getting Install Date for: $instance" 
					$sql = "SELECT schemadate FROM sysservers"
					[DbaDateTime]$sqlInstallDate = $server.Query($sql, 'master', $true).create_date
				}											

			} 

			if ($SqlOnly -ne $true)			
			{ 
				Write-Message -Level Verbose -Message "Getting Windows Server Name for: $servername" 
				$WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $Credential).ComputerName
				
				try
				{
					Write-Message -Level Verbose -Message "Getting Windows Install date via CIM for: $WindowsServerName"
					[DbaDateTime]$windowsInstallDate = (Get-DbaCmObject -ComputerName $WindowsServerName -ClassName win32_OperatingSystem -Credential $WindowsCredential).InstallDate					
				}
				catch
				{
					try
					{	
						Write-Message -Level Verbose -Message "Getting Windows Install date via DCOM for: $WindowsServerName" 
						$CimOption = New-CimSessionOption -Protocol DCOM
						$CimSession = New-CimSession -Credential:$Credential -ComputerName $WindowsServerName -SessionOption $CimOption
						[DbaDateTime]$windowsInstallDate = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).InstallDate					
					}
					catch
					{
						Stop-Function -Message "Failed to connect to: $WindowsServerName" -Continue -Target $instance -InnerErrorRecord $_
					}
				}
			}

			$object = [PSCustomObject]@{
							ComputerName = $( if ( $server.NetName) { $server.NetName } else { $WindowsServerName } ) 
							InstanceName = $server.ServiceName
							SqlServer = $server.InstanceName
							SqlInstallDate = $sqlInstallDate
							WindowsInstallDate = $windowsInstallDate
						}

			if ($sqlOnly) 
			{
				Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlServer, SqlInstallDate
			}
			elseif ($WindowsOnly) 
			{
				Select-DefaultView -InputObject $object -Property ComptuerName, WindowsInstallDate
			}
			else 
			{
				Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlServer, SqlInstallDate, WindowsInstallDate
			}

        } 
    }
}