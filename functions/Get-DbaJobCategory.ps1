#ValidationTags#Messaging,FlowControl,CodeStyle#
function Get-DbaJobCategory {
    <#
        .SYNOPSIS
            Gets SQL Agent Job Category information for each instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaJobCategory returns connected SMO object for SQL Agent Job Category information for each instance(s) of SQL Server.

        .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Agent, Job, Category
            Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaJobCategory

        .EXAMPLE
            Get-DbaJobCategory -SqlInstance localhost

            Returns all SQL Agent Job Categories on the local default SQL Server instance

        .EXAMPLE
            Get-DbaJobCategory -SqlInstance localhost, sql2016

            Returns all SQL Agent Job Categories for the local and sql2016 SQL Server instances
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($jobCategory in $server.JobServer.JobCategories) {
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name ComputerName -value $jobCategory.Parent.Parent.NetName
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name InstanceName -value $jobCategory.Parent.Parent.ServiceName
                Add-Member -Force -InputObject $jobCategory -MemberType NoteProperty -Name SqlInstance -value $jobCategory.Parent.Parent.DomainInstanceName

                Select-DefaultView -InputObject $jobCategory -Property ComputerName, InstanceName, SqlInstance, ID, Name, CategoryType
            }
        }
    }
}