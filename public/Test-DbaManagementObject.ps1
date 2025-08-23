function Test-DbaManagementObject {
    <#
    .SYNOPSIS
        Verifies if specific SQL Server Management Objects (SMO) library versions are installed on target computers.

    .DESCRIPTION
        Checks the Global Assembly Cache (GAC) for Microsoft.SqlServer.Smo assemblies of specified versions. This function helps DBAs ensure the required SMO libraries are available before executing scripts that depend on specific SQL Server client tool versions. Returns detailed results showing which versions exist on each target computer, preventing runtime errors when SMO-dependent automation runs against systems with missing or incompatible client libraries.

    .PARAMETER ComputerName
        Specifies the target computer(s) to check for SMO assemblies. Accepts pipeline input and defaults to the local computer.
        Use this when verifying SMO library versions across multiple servers in your environment.

    .PARAMETER Credential
        This command uses Windows credentials. This parameter allows you to connect remotely as a different user.

    .PARAMETER VersionNumber
        Specifies the major version number(s) of SQL Server SMO assemblies to verify in the Global Assembly Cache.
        Common values include 11 (SQL 2012), 12 (SQL 2014), 13 (SQL 2016), 14 (SQL 2017), 15 (SQL 2019), and 16 (SQL 2022).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SMO
        Author: Ben Miller (@DBAduck), dbaduck.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaManagementObject

    .EXAMPLE
        PS C:\> Test-DbaManagementObject -VersionNumber 13

        Returns True if the version exists, if it does not exist it will return False

    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [int[]]$VersionNumber,
        [switch]$EnableException
    )

    begin {
        $scriptBlock = {
            foreach ($number in $args) {
                $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending).Name
                if (-not $smoList) {
                    $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\Microsoft.NET\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "*$number.*" -ErrorAction SilentlyContinue | Where-Object FullName -match "_$number" | Sort-Object Name -Descending).Name
                }

                if ($smoList) {
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $number
                        Exists       = $true
                    }
                } else {
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $number
                        Exists       = $false
                    }
                }
            }
        }
    }
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptBlock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
            } catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer
            }
        }
    }
}