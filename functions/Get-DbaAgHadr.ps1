function Get-DbaAgHadr {
    <#
        .SYNOPSIS
            Gets the Hadr service setting on the specified SQL Server instance.

        .DESCRIPTION
            Gets the Hadr setting, from the service level, and returns true or false for the specified SQL Server instance.

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER Credential
            Credential object used to connect to the Windows server itself as a different user

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup
            Author: Shawn Melton (@wsmelton | http://blog.wsmelton.info)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaAgHadr

        .EXAMPLE
            Get-DbaAgHadr -SqlInstance sql2016

            Returns a status of the Hadr setting for sql2016 SQL Server instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$Credential,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {

            try {
                $computer = $instance.ComputerName
                $instanceName = $instance.InstanceName
                $computerName = (Resolve-DbaNetworkName -ComputerName $computer -Credential $Credential).FullComputerName
                Write-Message -Level Verbose -Message "Attempting to connect to $computer"
                $currentState = Invoke-ManagedComputerCommand -ComputerName $computerName -ScriptBlock { $wmi.Services[$args[0]] | Select-Object IsHadrEnabled } -ArgumentList $instanceName -Credential $Credential
            }
            catch {
                Stop-Function -Message "Failure connecting to $computer" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            [PSCustomObject]@{
                ComputerName  = $computerName
                InstanceName  = $instanceName
                SqlInstance   = $instance.FullName
                IsHadrEnabled = $currentState.IsHadrEnabled
            }
        }
    }
}