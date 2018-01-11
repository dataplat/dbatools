function Get-DbaAgentOperator {
    <#
        .SYNOPSIS
            Returns all SQL Agent operators on a SQL Server Agent.

        .DESCRIPTION
            This function returns SQL Agent operators.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.
            This can be a collection and receive pipeline input.

        .PARAMETER SqlCredential
            PSCredential object to connect as. If not specified, current Windows login will be used.

        .PARAMETER Operator
            The operator(s) to process - this list is auto-populated from the server. If unspecified, all operators will be processed.

        .PARAMETER ExcludeOperator
            The operator(s) to exclude - this list is auto-populated from the server

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Agent, Operator
            Author: Klaas Vandenberghe ( @PowerDBAKlaas )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Get-DbaAgentOperator

        .EXAMPLE
            Get-DbaAgentOperator -SqlInstance ServerA,ServerB\instanceB

            Returns any SQL Agent operators on serverA and serverB\instanceB

        .EXAMPLE
            'ServerA','ServerB\instanceB' | Get-DbaAgentOperator

            Returns all SQL Agent operators  on serverA and serverB\instanceB

        .EXAMPLE
            Get-DbaAgentOperator -SqlInstance ServerA -Operator Dba1,Dba2

            Returns only the SQL Agent Operators Dba1 and Dba2 on ServerA.

        .EXAMPLE
            Get-DbaAgentOperator -SqlInstance ServerA,ServerB -ExcludeOperator Dba3

            Returns all the SQL Agent operators on ServerA and ServerB, except the Dba3 operator.
    #>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Operator,
        [object[]]$ExcludeOperator,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue -Target $server
            }

            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "Enabled as IsEnabled", "EmailAddress", "LastEmail"

            if ($Operator) {
                $operators = $server.JobServer.Operators | Where-Object Name -In $Operator
            }
            elseif ($ExcludeOperator) {
                $operators = $server.JobServer.Operators | Where-Object Name -NotIn $ExcludeOperator
            }
            else {
                $operators = $server.JobServer.Operators
            }

            foreach ($operat in $operators) {

                $jobs = $server.JobServer.jobs | Where-Object { $_.OperatorToEmail, $_.OperatorToNetSend, $_.OperatorToPage -contains $operat.Name }
                $lastemail = [dbadatetime]$operat.LastEmailDate

                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name ComputerName -Value $server.NetName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name RelatedJobs -Value $jobs
                Add-Member -Force -InputObject $operat -MemberType NoteProperty -Name LastEmail -Value $lastemail
                Select-DefaultView -InputObject $operat -Property $defaults
            }
        }
    }
}
