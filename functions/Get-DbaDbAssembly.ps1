#ValidationTags#Messaging,FlowControl,CodeStyle#
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
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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

    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($database in ($server.Databases | Where-Object IsAccessible)) {
                try {
                    foreach ($assembly in $database.assemblies) {

                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name ComputerName -value $assembly.Parent.Parent.ComputerName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name InstanceName -value $assembly.Parent.Parent.ServiceName
                        Add-Member -Force -InputObject $assembly -MemberType NoteProperty -Name SqlInstance -value $assembly.Parent.Parent.DomainInstanceName

                        Select-DefaultView -InputObject $assembly -Property ComputerName, InstanceName, SqlInstance, ID, Name, Owner, 'AssemblySecurityLevel as SecurityLevel', CreateDate, IsSystemObject, Version
                    }
                } catch {
                    Stop-Function -Message "Issue pulling assembly information" -Target $assembly -ErrorRecord $_ -Continue
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Get-DbaDatabaseAssembly
    }
}