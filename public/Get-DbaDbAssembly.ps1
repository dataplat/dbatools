function Get-DbaDbAssembly {
    <#
    .SYNOPSIS
        Retrieves CLR assemblies registered in SQL Server databases for security auditing and inventory management.

    .DESCRIPTION
        Retrieves detailed information about Common Language Runtime (CLR) assemblies that have been registered in SQL Server databases. This function helps DBAs audit custom .NET assemblies for security compliance, track assembly versions, and identify potentially unsafe or unauthorized code deployed to their SQL Server instances. Returns key properties including assembly security level, owner, creation date, and version information across all accessible databases.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to scan for CLR assemblies. Accepts wildcards for pattern matching.
        Use this when auditing assemblies in specific databases rather than scanning the entire instance.

    .PARAMETER Name
        Filters results to assemblies with matching names. Supports exact assembly name matching only.
        Use this when investigating specific assemblies during security audits or troubleshooting CLR-related issues.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Assembly, Database
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbAssembly

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Assembly

        Returns one Assembly object for each CLR assembly found in the specified or accessible databases.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database name containing the assembly
        - ID: Unique identifier for the assembly
        - Name: Name of the assembly
        - Owner: The principal that owns the assembly
        - SecurityLevel: Assembly security level (Safe, ExternalAccess, or Unsafe)
        - CreateDate: DateTime when the assembly was created
        - IsSystemObject: Boolean indicating if the assembly is a system object
        - Version: Version information of the assembly

        Additional properties available (from SMO Assembly object):
        - DatabaseId: Unique identifier for the database containing the assembly
        - FilePath: File path associated with the assembly
        - AssemblySecurityLevel: Same as SecurityLevel property

        All properties from the base SMO Assembly object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDbAssembly -SqlInstance localhost

        Returns all Database Assembly on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbAssembly -SqlInstance localhost, sql2016

        Returns all Database Assembly for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaDbAssembly -SqlInstance Server1 -Database MyDb -Name MyTechCo.Houids.SQLCLR

        Will fetch details for the MyTechCo.Houids.SQLCLR assembly in the MyDb Database on the Server1 instance

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Name,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $databases = $server.Databases | Where-Object IsAccessible
            if (Test-Bound 'Database') {
                $databases = $databases | Where-Object Name -in $Database
            }
            foreach ($db in $databases) {
                try {
                    $assemblies = $db.assemblies
                    if (Test-Bound 'Name') {
                        $assemblies = $assemblies | Where-Object Name -in $Name
                    }
                    foreach ($assembly in $assemblies) {

                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name ComputerName -value $assembly.Parent.Parent.ComputerName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name InstanceName -value $assembly.Parent.Parent.ServiceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name SqlInstance -value $assembly.Parent.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name Database -value $db.name
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name DatabaseId -value $db.Id

                        Select-DefaultView -InputObject $assembly -Property ComputerName, InstanceName, SqlInstance, Database, ID, Name, Owner, 'AssemblySecurityLevel as SecurityLevel', CreateDate, IsSystemObject, Version
                    }
                } catch {
                    Stop-Function -Message "Issue pulling assembly information" -Target $assembly -ErrorRecord $_ -Continue
                }
            }
        }
    }
}