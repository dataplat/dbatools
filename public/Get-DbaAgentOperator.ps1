function Get-DbaAgentOperator {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent operators with their notification settings and related jobs and alerts.

    .DESCRIPTION
        Retrieves detailed information about SQL Server Agent operators, including email addresses, enabled status, and relationships to jobs and alerts that notify them. Essential for auditing notification configurations, troubleshooting alert delivery issues, and maintaining disaster recovery contact lists. Shows which jobs notify each operator and tracks the last time each operator received email notifications, helping DBAs verify their monitoring and alerting infrastructure is properly configured.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        Specifies which SQL Agent operators to retrieve by name. Accepts an array of operator names for targeting specific notification contacts.
        Use this when you need to check configuration or troubleshoot notification issues for particular operators instead of reviewing all operators on the instance.

    .PARAMETER ExcludeOperator
        Excludes specified SQL Agent operators from the results by name. Useful for filtering out test operators or disabled contacts during audits.
        Commonly used when reviewing active notification configurations while ignoring legacy or temporary operator accounts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Operator
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentOperator

    .EXAMPLE
        PS C:\> Get-DbaAgentOperator -SqlInstance ServerA,ServerB\instanceB

        Returns any SQL Agent operators on serverA and serverB\instanceB

    .EXAMPLE
        PS C:\> 'ServerA','ServerB\instanceB' | Get-DbaAgentOperator

        Returns all SQL Agent operators  on serverA and serverB\instanceB

    .EXAMPLE
        PS C:\> Get-DbaAgentOperator -SqlInstance ServerA -Operator Dba1,Dba2

        Returns only the SQL Agent Operators Dba1 and Dba2 on ServerA.

    .EXAMPLE
        PS C:\> Get-DbaAgentOperator -SqlInstance ServerA,ServerB -ExcludeOperator Dba3

        Returns all the SQL Agent operators on ServerA and ServerB, except the Dba3 operator.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Operator,
        [object[]]$ExcludeOperator,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue -Target $server
            }

            $defaults = "ComputerName", "InstanceName", "SqlInstance", "Name", "ID", "Enabled as IsEnabled", "EmailAddress", "LastEmail"

            if ($Operator) {
                $operators = $server.JobServer.Operators | Where-Object Name -In $Operator
            } elseif ($ExcludeOperator) {
                $operators = $server.JobServer.Operators | Where-Object Name -NotIn $ExcludeOperator
            } else {
                $operators = $server.JobServer.Operators
            }

            $alerts = $server.JobServer.alerts

            foreach ($operat in $operators) {

                $jobs = $server.JobServer.jobs | Where-Object { $_.OperatorToEmail, $_.OperatorToNetSend, $_.OperatorToPage -contains $operat.Name }
                $lastemail = [dbadatetime]$operat.LastEmailDate

                $operatAlerts = @()
                foreach ($alert in $alerts) {
                    $dtAlert = $alert.EnumNotifications($operat.Name)
                    if ($dtAlert.Rows.Count -gt 0) {
                        $operatAlerts += $alert.Name
                        $alertlastemail = [dbadatetime]$alert.LastOccurrenceDate
                    }
                }

                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name RelatedJobs -Value $jobs
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name LastEmail -Value $lastemail
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name RelatedAlerts -Value $operatAlerts
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name AlertLastEmail -Value $alertlastemail
                Select-DefaultView -InputObject $operat -Property $defaults
            }
        }
    }
}