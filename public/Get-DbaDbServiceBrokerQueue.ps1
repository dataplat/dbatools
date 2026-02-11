function Get-DbaDbServiceBrokerQueue {
    <#
    .SYNOPSIS
        Gets database service broker queues

    .DESCRIPTION
        Gets database Sservice broker queue

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to retrieve Service Broker queues from. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to exclude from the Service Broker queue retrieval. Accepts wildcards for pattern matching.
        Useful when you want to scan most databases but skip specific ones like test or development databases.

    .PARAMETER ExcludeSystemQueue
        Excludes system-created Service Broker queues from the results, showing only user-created queues.
        Use this to focus on application-specific queues and filter out SQL Server's internal messaging queues.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, ServiceBroker, Queue
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbServiceBrokerQueue

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Broker.ServiceQueue

        Returns one ServiceQueue object per queue found across the specified databases. System queues are included by default but can be excluded using the -ExcludeSystemQueue parameter.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database containing the queue
        - Schema: The schema containing the queue
        - QueueID: The unique object ID of the queue within the database
        - CreateDate: DateTime when the queue was created
        - DateLastModified: DateTime when the queue was last modified
        - Name: The name of the Service Broker queue
        - ProcedureName: Name of the stored procedure that activates the queue (if configured)
        - ProcedureSchema: Schema containing the activation procedure

        Additional properties available (from SMO Broker.ServiceQueue object):
        - IsSystemObject: Boolean indicating if this is a system queue created by SQL Server
        - IsActivationEnabled: Boolean indicating if queue activation is enabled
        - MaxReaders: Maximum number of simultaneous queue readers
        - State: Queue state (Available, Unavailable, etc.)
        - Owner: The principal that owns the queue
        - Urn: The Urn identifier for the queue

        All properties from the base SMO ServiceBrokerQueue object are accessible via Select-Object * even though only default properties are displayed.

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerQueue -SqlInstance sql2016

        Gets all database service broker queues

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerQueue -SqlInstance Server1 -Database db1

        Gets the service broker queues for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerQueue -SqlInstance Server1 -ExcludeDatabase db1

        Gets the service broker queues for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerQueue -SqlInstance Server1 -ExcludeSystemQueue

        Gets the service broker queues for all databases that are not system objects

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemQueue,
        [switch]$EnableException
    )

    process {
        if (Test-Bound SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db is not accessible. Skipping."
                continue
            }
            if ($db.ServiceBroker.Queues.Count -eq 0) {
                Write-Message -Message "No Service Broker Queues exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            foreach ($queue in $db.ServiceBroker.Queues) {
                if ( (Test-Bound -ParameterName ExcludeSystemQueue) -and $queue.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $queue -MemberType NoteProperty -Name ComputerName -value $queue.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $queue -MemberType NoteProperty -Name InstanceName -value $queue.Parent.Parent.InstanceName
                Add-Member -Force -InputObject $queue -MemberType NoteProperty -Name SqlInstance -value $queue.Parent.Parent.SqlInstance
                Add-Member -Force -InputObject $queue -MemberType NoteProperty -Name Database -value $db.Name

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Schema', 'ID as QueueID', 'CreateDate', 'DateLastModified', 'Name', 'ProcedureName', 'ProcedureSchema'
                Select-DefaultView -InputObject $queue -Property $defaults
            }
        }
    }
}