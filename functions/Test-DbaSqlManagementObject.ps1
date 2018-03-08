function Test-DbaSqlManagementObject {
    <#
        .SYNOPSIS
            Tests to see if the SMO version specified exists on the computer.

        .DESCRIPTION
            The Test-DbaSqlManagementObject returns True if the Version is on the computer, and False if it does not exist.

        .PARAMETER ComputerName
            The name of the target you would like to check

        .PARAMETER Credential
            This command uses Windows credentials. This parameter allows you to connect remotely as a different user.

        .PARAMETER VersionNumber
            This is the specific version number you are looking for and the return will be True.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SMO
            Author: Ben Miller (@DBAduck - http://dbaduck.com)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaSqlManagementObject

        .EXAMPLE
            Test-DbaSqlManagementObject -VersionNumber 13

            Returns True if the version exists, if it does not exist it will return False
    #>
    [CmdletBinding()]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer", "SqlInstance")]
        [DbaInstance[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [int[]]$VersionNumber,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $scriptblock = {
            foreach ($number in $args) {
                $smoList = (Get-ChildItem -Path "$($env:SystemRoot)\assembly\GAC_MSIL\Microsoft.SqlServer.Smo" -Filter "$number.*" | Sort-Object Name -Descending).Name

                if ($smoList) {
                    [pscustomobject]@{
                        ComputerName = $env:COMPUTERNAME
                        Version      = $number
                        Exists       = $true
                    }
                }
                else {
                    [pscustomobject]@{
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
                Invoke-Command2 -ComputerName $computer -ScriptBlock $scriptblock -Credential $Credential -ArgumentList $VersionNumber -ErrorAction Stop
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}