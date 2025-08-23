function Get-DbaRgClassifierFunction {
    <#
    .SYNOPSIS
        Retrieves the Resource Governor classifier function configured for workload group assignment

    .DESCRIPTION
        Retrieves the custom classifier function that Resource Governor uses to determine which workload group incoming connections are assigned to. The classifier function contains the business logic that evaluates connection properties (like login name, application name, or host name) and returns the appropriate workload group name. This function is always stored in the master database and is essential for understanding how Resource Governor categorizes and manages SQL Server workloads.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER InputObject
        Accepts Resource Governor objects piped from Get-DbaResourceGovernor.
        Use this when processing multiple instances or when you already have Resource Governor objects to work with, allowing for efficient pipeline operations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, ResourceGovernor
        Author: Alessandro Alpi (@suxstellino), alessandroalpi.blog

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRgClassifierFunction

    .EXAMPLE
        PS C:\> Get-DbaRgClassifierFunction -SqlInstance sql2016

        Gets the classifier function from sql2016

    .EXAMPLE
        PS C:\> 'Sql1','Sql2/sqlexpress' | Get-DbaResourceGovernor | Get-DbaRgClassifierFunction

        Gets the classifier function object on Sql1 and Sql2/sqlexpress instances

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.ResourceGovernor[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaResourceGovernor -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        foreach ($resourcegov in $InputObject) {
            $server = $resourcegov.Parent
            $classifierFunction = $null

            foreach ($currentFunction in $server.Databases["master"].UserDefinedFunctions) {
                $fullyQualifiedFunctionName = [string]::Format("[{0}].[{1}]", $currentFunction.Schema, $currentFunction.Name)
                if ($fullyQualifiedFunctionName -eq $InputObject.ClassifierFunction) {
                    $classifierFunction = $currentFunction
                }
            }

            if ($classifierFunction) {
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name ComputerName -value $resourcegov.ComputerName
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name InstanceName -value $resourcegov.InstanceName
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name SqlInstance -value $resourcegov.SqlInstance
                Add-Member -Force -InputObject $classifierFunction -MemberType NoteProperty -Name Database -value 'master'
            }

            Select-DefaultView -InputObject $classifierFunction -Property ComputerName, InstanceName, SqlInstance, Database, Schema, CreateDate, DateLastModified, Name, DataType
        }
    }
}