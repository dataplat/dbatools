function Get-DbaDbServiceBrokerService {
    <#
    .SYNOPSIS
        Retrieves Service Broker services from SQL Server databases for auditing and troubleshooting messaging configurations

    .DESCRIPTION
        Retrieves detailed information about Service Broker services configured in SQL Server databases, including service names, associated queues, schemas, and ownership details. Service Broker services define the endpoints for reliable messaging between applications and databases. This function helps DBAs audit Service Broker implementations, troubleshoot message-based applications, and document messaging configurations for compliance or migration planning.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to query for Service Broker services. Accepts multiple database names.
        Use this when you need to limit the search to specific databases instead of scanning all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the Service Broker service search. Accepts multiple database names.
        Useful when you want to audit most databases but skip known databases without Service Broker configurations.

    .PARAMETER ExcludeSystemService
        Excludes system-created Service Broker services from the results, showing only user-defined services.
        Use this to focus on custom messaging implementations and avoid clutter from built-in SQL Server services.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Service, ServiceBroker
        Author: Ant Green (@ant_green)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbServiceBrokerService

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerService -SqlInstance sql2016

        Gets all database service broker queues

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerService -SqlInstance Server1 -Database db1

        Gets the service broker queues for the db1 database

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerService -SqlInstance Server1 -ExcludeDatabase db1

        Gets the service broker queues for all databases except db1

    .EXAMPLE
        PS C:\> Get-DbaDbServiceBrokerService -SqlInstance Server1 -ExcludeSystemService

        Gets the service broker queues for all databases that are not system objects

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemService,
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
            if ($db.ServiceBroker.Services.Count -eq 0) {
                Write-Message -Message "No Service Broker Services exist in the $db database on $instance" -Target $db -Level Output
                continue
            }

            foreach ($service in $db.ServiceBroker.Services) {
                if ( (Test-Bound -ParameterName ExcludeSystemService) -and $service.IsSystemObject ) {
                    continue
                }

                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -value $service.Parent.Parent.ComputerName
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name InstanceName -value $service.Parent.Parent.InstanceName
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name SqlInstance -value $service.Parent.Parent.SqlInstance
                Add-Member -Force -InputObject $service -MemberType NoteProperty -Name Database -value $db.Name

                $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Owner', 'ID as ServiceID', 'Name', 'QueueSchema', 'QueueName'
                Select-DefaultView -InputObject $service -Property $defaults
            }
        }
    }
}