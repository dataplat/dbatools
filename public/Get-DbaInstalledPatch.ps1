function Get-DbaInstalledPatch {
    <#
    .SYNOPSIS
        Retrieves installed SQL Server patches from Windows Registry for patch compliance and audit reporting.

    .DESCRIPTION
        Queries the Windows Registry to retrieve a complete history of SQL Server patches installed on one or more computers. This includes Cumulative Updates (CUs), Service Packs, and Hotfixes that have been applied to any SQL Server instance on the target machines.

        Essential for patch compliance audits, pre-upgrade planning, and troubleshooting environments where you need to verify what patches have been installed and when. The function returns patch names, versions, and installation dates so you can quickly assess patch levels across your SQL Server estate without manually checking each server.

        To test if your build is up to date, use Test-DbaBuild.

    .PARAMETER ComputerName
        Specifies the target computers to query for SQL Server patch information. Accepts single computer names, comma-separated lists, or pipeline input from text files.
        Use this to audit patch levels across multiple servers for compliance reporting or pre-upgrade planning.
        Defaults to the local computer when not specified.

    .PARAMETER Credential
        Credential object used to connect to the Computer as a different user.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server patch found on the target computer(s). Patches are filtered from the Windows Registry to include only those with "Hotfix" or "Service Pack" in their display name and "SQL" anywhere in the name.

        Properties:
        - ComputerName: The name of the computer where the patch was found
        - Name: The display name of the patch as shown in Windows Registry (e.g., "Hotfix for SQL Server 2019 (KB5012345)")
        - Version: The version number of the patch as stored in Registry
        - InstallDate: The installation date converted to DbaDate type; use .Date property for date-only access or .DateTime for full datetime

    .NOTES
        Tags: Deployment, Updates, Patches
        Author: Hiram Fleitas, @hiramfleitas, fleitasarts.com
        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstalledPatch

    .EXAMPLE
        PS C:\> Get-DbaInstalledPatch -ComputerName HiramSQL1, HiramSQL2

        Gets a list of SQL Server patches installed on HiramSQL1 and HiramSQL2.

    .EXAMPLE
        PS C:\> Get-Content C:\Monitoring\Servers.txt | Get-DbaInstalledPatch

        Gets the SQL Server patches from a list of computers in C:\Monitoring\Servers.txt.

    .EXAMPLE
        PS C:\> Get-DbaInstalledPatch -ComputerName SRV1 | Sort-Object InstallDate.Date

        Gets the SQL Server patches from SRV1 and orders by date. Note that we use
        a special customizable date datatype for InstallDate so you'll need InstallDate.Date

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    process {
        foreach ($computer in $ComputerName.ComputerName) {
            try {
                $patches = Invoke-Command2 -ComputerName $computer -Credential $Credential -ScriptBlock {
                    Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object { $_.DisplayName -like "Hotfix*SQL*" -or $_.DisplayName -like "Service Pack*SQL*" } | Sort-Object InstallDate
                }
            } catch {
                Stop-Function -Message "Failed" -Continue -Target $computer -ErrorRecord $_
            }

            foreach ($patch in $patches) {
                [PSCustomObject]@{
                    ComputerName = $computer
                    Name         = $patch.DisplayName
                    Version      = $patch.DisplayVersion
                    InstallDate  = [DbaDate][datetime]::ParseExact($patch.InstallDate, 'yyyyMMdd', $null)
                }
            }
        }
    }
}