function Get-DbaResourceGovernorClassiferFunction {
    <#
.SYNOPSIS
Gets the Resource Governor custom classifier Function

.DESCRIPTION
Gets the Resource Governor custom classifier Function which is used for customize the workload groups usage

.PARAMETER SqlInstance
The target SQL Server instance(s)

.PARAMETER SqlCredential
Allows you to login to SQL Server using alternative credentials

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Tags: Migration, ResourceGovernor
Author: Alessandro Alpi (@suxstellino), alessandroalpi.blog
Requires: sysadmin access on SQL Servers

Website: https://dbatools.io
Copyright: (C) Alessandro Alpi, sux.stellino@gmail.com
License: MIT https://opensource.org/licenses/MIT

.EXAMPLE
Get-DbaResourceGovernorClassiferFunction -SqlInstance sql2016

Gets the classifier function object of the SqlInstance

.EXAMPLE
'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernorClassiferFunction

Gets the classifier function object on Sql1 and Sql2/sqlexpress instances

#>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential

                if ($server.VersionMajor -lt 10) {
                    Stop-Function -Message "Resource Governor is only supported in SQL Server 2008 and above. Quitting."
                    return
                }
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $db = $server.Databases["master"]
            $resourceGovernor = $server.ResourceGovernor
            
            $classifierFunction = $null
            foreach ($currentFunction in $db.UserDefinedFunctions)
            {
                $fullyQualifiedFunctionName = [string]::Format("[{0}].[{1}]", $currentFunction.Schema, $currentFunction.Name)
                if ($fullyQualifiedFunctionName -eq $resourceGovernor.ClassifierFunction)
                {
                    $classifierFunction = $currentFunction
                }
            }
            
            if ($classifierFunction) {
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name Database -value $db.Name
            }

            Select-DefaultView -InputObject $classifierFunction -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name, DataType
        }
    }
}