function Get-DbaFilestream {
	<#
        .SYNOPSIS
            Returns the status of FileStream on specified SQL Server instances

        .DESCRIPTION
            Connects to the specified SQL Server instances, and returns the status of the FileStream feature

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Filestream
            Author: Stuart Moore ( @napalmgram )

            dbatools PowerShell module (https://dbatools.io)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaFilestream

        .EXAMPLE
            Get-DbaFilestream -SqlInstance server1\instance2

            Will return the status of FileStream configuration for the service and instance server1\instance2
    #>
	[CmdletBinding()]
	param(
		[parameter(ValueFromPipeline = $true, Position = 1)]
		[DbaInstance[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[PSCredential]$Credential,
		[Alias('Silent')]
		[switch]$EnableException
	)
	begin {
		$idServiceFS =[ordered]@{
			0 = 'Disabled'
			1 = 'Transact-SQL access'
			2 = 'Transact-SQL and I/O access'
			3 = 'Transact-SQL, I/O and remote client access'
		}
		$idInstanceFS =[ordered]@{
			0 = 'Disabled'
			1 = 'Transact-SQL access enabled'
			2 = 'Full access enabled'
		}
	}
	process {
		foreach ($instance in $SqlInstance) {
			$computer = $instance.ComputerName
			$instanceName = $instance.InstanceName

			<# Get Service-Level information #>
			if ($instance.IsLocalHost) {
				$computerName = $computer
			}
			else {
				$computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName
			}

			Write-Message -Level Verbose -Message "Attempting to connect to $computer"
			try {
				$namespace = Get-DbaCmObject -ComputerName $computerName -Namespace root\Microsoft\SQLServer -Query "SELECT NAME FROM __NAMESPACE WHERE NAME LIKE 'ComputerManagement%'" | Where-Object { (Get-DbaCmObject -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName FilestreamSettings).Count -gt 0} | Sort-Object Name -Descending | Select-Object -First 1

				if ($namespace.Name) {
					$serviceFS = Get-DbaCmObject -ComputerName $computerName -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName FilestreamSettings | Where-Object InstanceName -eq $instanceName | Select-Object -First 1
				}
				else {
					Write-Message -Level Warning -Message "No ComputerManagement was found on $computer. Service level information may not be collected." -Target $computer
				}
			}
			catch {
				Stop-Function -Message "Issue collecting service-level information on $computer for $instanceName" -Target $computer -ErrorRecord $_ -Exception $_.Exception -Continue
			}

			<# Get Instance-Level information #>
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance."
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 10
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

			try {
				$instanceFS = Get-DbaSpConfigure -SqlInstance $server -ConfigName FilestreamAccessLevel | Select-Object ConfiguredValue, RunningValue
			}
			catch {
				Stop-Function -Message "Issue collectin instance-level configuration on $instanceName" -Target $server -ErrorRecord $_ -Exception $_.Exception -Continue
			}

			$pendingRestart = $instanceFS.ConfiguredValue -ne $instanceFS.RunningValue

			$isConfigured = ($serviceFS.AccessLevel -ne 0) -and ($instanceFS.RuningValue -ne 0)

			[PsCustomObject]@{
				ComputerName            = $server.NetName
				InstanceName            = $server.ServiceName
				SqlInstance             = $server.DomainInstanceName
				ServiceAccessLevel      = $serviceFS.AccessLevel
				ServiceAccessLevelDesc  = $idServiceFS[[int]$serviceFS.AccessLevel]
				ServiceShareName        = $serviceFS.ShareName
				InstanceAccessLevel     = $instanceFS.RunningValue
				InstanceAccessLevelDesc = $idInstanceFS[[int]$instanceFS.RunningValue]
				IsConfigured            = $isConfigured
				PendingRestart          = $pendingRestart
			} | Select-DefaultView -Exclude ServiceAccessLevel, InstanceAccessLevel
		}
	}
}