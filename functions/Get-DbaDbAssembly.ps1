function Get-DbaDbAssembly {
    <#
    .SYNOPSIS
        Gets SQL Database Assembly information for each instance(s) of SQL Server.

    .DESCRIPTION
        The Get-DbaDbAssembly command gets SQL Database Assembly information for each instance(s) of SQL Server.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specify a Database to be checked for assembly. If not specified, all databases in the specified Instance(s) will be checked

    .PARAMETER Name
        Specify an Assembly to be fetched. If not specified all Assemblys will be returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Assembly, Database
        Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbAssembly

    .EXAMPLE
        PS C:\> Get-DbaDbAssembly -SqlInstance localhost

        Returns all Database Assembly on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaDbAssembly -SqlInstance localhost, sql2016

        Returns all Database Assembly for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaDbAssemly -SqlInstance Server1 -Database MyDb -Name MyTechCo.Houids.SQLCLR

        Will fetch details for the MyTechCo.Houids.SQLCLR assemlby in the MyDb Database on the Server1 instance

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Object[]]$Database,
        [string[]]$Name,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            $databases = $server.Databases | Where-Object IsAccessible
            if (Test-Bound 'Database') {
                $databases = $databases | Where-Object Name -in $Database
            }
            foreach ($db in $databases) {
                try {
                    if (Test-Bound 'Name') {
                        $assemblies = $assemblies | Where-Object Name -in  $Name
                    } else {
                        $assemblies = $db.assemblies
                    }
                    foreach ($assembly in $assemblies) {

                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name ComputerName -value $assembly.Parent.Parent.ComputerName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name InstanceName -value $assembly.Parent.Parent.ServiceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name SqlInstance -value $assembly.Parent.Parent.DomainInstanceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name Database -value $db.name

                        Select-DefaultView -InputObject $assembly -Property ComputerName, InstanceName, SqlInstance, Database, ID, Name, Owner, 'AssemblySecurityLevel as SecurityLevel', CreateDate, IsSystemObject, Version
                    }
                } catch {
                    Stop-Function -Message "Issue pulling assembly information" -Target $assembly -ErrorRecord $_ -Continue
                }
            }
        }
    }
}