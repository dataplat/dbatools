function Test-DbaTempDbConfig {
    <#
    .SYNOPSIS
        Evaluates tempdb against several rules to match best practices.

    .DESCRIPTION
        Evaluates tempdb against a set of rules to match best practices. The rules are:

        * TF 1118 enabled - Is Trace Flag 1118 enabled (See KB328551).
        * File Count - Does the count of data files in tempdb match the number of logical cores, up to 8?
        * File Growth - Are any files set to have percentage growth? Best practice is all files have an explicit growth value.
        * File Location - Is tempdb located on the C:\? Best practice says to locate it elsewhere.
        * File MaxSize Set (optional) - Do any files have a max size value? Max size could cause tempdb problems if it isn't allowed to grow.
        * Data File Size Equal - Are the sizes of all the tempdb data files the same?

        Other rules can be added at a future date.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. SQL Server 2005 and higher are supported.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Tempdb, Configuration
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Based on Amit Bannerjee's (@banerjeeamit) Get-TempDB function (https://github.com/amitmsft/SqlOnAzureVM/blob/master/Get-TempdbFiles.ps1)

    .LINK
        https://dbatools.io/Test-DbaTempDbConfig

    .EXAMPLE
        PS C:\> Test-DbaTempDbConfig -SqlInstance localhost

        Checks tempdb on the localhost machine.

    .EXAMPLE
        PS C:\> Test-DbaTempDbConfig -SqlInstance localhost | Select-Object *

        Checks tempdb on the localhost machine. All rest results are shown.

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sqlserver2014a | Test-DbaTempDbConfig | Select-Object * | Out-GridView

        Checks tempdb configuration for a group of servers from SQL Server Central Management Server (CMS). Output includes all columns. Send output to GridView.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # removed previous assumption that 2016+ will have it enabled
            $tfCheck = $server.Databases['tempdb'].Query("DBCC TRACEON (3604);DBCC TRACESTATUS(-1)")
            $current = ($tfCheck.TraceFlag -join ',').Contains('1118')

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'TF 1118 Enabled'
                Recommended    = $true
                CurrentSetting = $current
                IsBestPractice = $current -eq $true
                Notes          = 'KB328551 describes how TF 1118 can benefit performance. SQL Server 2016 has this functionality enabled by default.'
            }

            Write-Message -Level Verbose -Message "TF 1118 evaluated"

            #get files and log files
            $tempdbFiles = Get-DbaDbFile -SqlInstance $server -Database tempdb
            [array]$dataFiles = $tempdbFiles | Where-Object Type -ne 1
            $logFiles = $tempdbFiles | Where-Object Type -eq 1
            Write-Message -Level Verbose -Message "TempDB file objects gathered"

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Count'
                Recommended    = [Math]::Min(8, $server.Processors)
                CurrentSetting = $dataFiles.Count
                IsBestPractice = $dataFiles.Count -eq [Math]::Min(8, $server.Processors)
                Notes          = 'Microsoft recommends that the number of tempdb data files is equal to the number of logical cores up to 8.'
            }

            Write-Message -Level Verbose -Message "File counts evaluated."

            #test file growth
            $percData = $dataFiles | Where-Object GrowthType -ne 'KB' | Measure-Object
            $percLog = $logFiles | Where-Object GrowthType -ne 'KB' | Measure-Object

            $totalCount = $percData.Count + $percLog.Count
            if ($totalCount -gt 0) {
                $totalCount = $true
            } else {
                $totalCount = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Growth in Percent'
                Recommended    = $false
                CurrentSetting = $totalCount
                IsBestPractice = $totalCount -eq $false
                Notes          = 'Set file growth to explicit values, not by percent.'
            }

            Write-Message -Level Verbose -Message "File growth settings evaluated."
            #test file Location

            $cdata = ($dataFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count + ($logFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count
            if ($cdata -gt 0) {
                $cdata = $true
            } else {
                $cdata = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Location'
                Recommended    = $false
                CurrentSetting = $cdata
                IsBestPractice = $cdata -eq $false
                Notes          = "Do not place your tempdb files on C:\."
            }

            Write-Message -Level Verbose -Message "File locations evaluated."

            #Test growth limits
            $growthLimits = ($dataFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count + ($logFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count
            if ($growthLimits -gt 0) {
                $growthLimits = $true
            } else {
                $growthLimits = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File MaxSize Set'
                Recommended    = $false
                CurrentSetting = $growthLimits
                IsBestPractice = $growthLimits -eq $false
                Notes          = "Consider setting your tempdb files to unlimited growth."
            }

            Write-Message -Level Verbose -Message "MaxSize values evaluated."

            #Test Data File Size Equal
            $distinctCountSizeDataFiles = ($dataFiles | Group-Object -Property Size | Measure-Object).Count

            if ($distinctCountSizeDataFiles -eq 1) {
                $equalSizeDataFiles = $true
            } else {
                $equalSizeDataFiles = $false
            }

            [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'Data File Size Equal'
                Recommended    = $true
                CurrentSetting = $equalSizeDataFiles
                IsBestPractice = $equalSizeDataFiles -eq $true
                Notes          = "Consider creating equally sized data files."
            }
            Write-Message -Level Verbose -Message "Data File Size Equal evaluated."
        }
    }
}