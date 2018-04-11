function Test-DbaTempDbConfiguration {
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

            Other rules can be added at a future date.

        .PARAMETER SqlInstance
            The SQL Server Instance to connect to. SQL Server 2005 and higher are supported.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Detailed
            Output all properties, will be depreciated in 1.0.0 release.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: tempdb, configuration
            Author: Michael Fal (@Mike_Fal), http://mikefal.net
            Based off of Amit Bannerjee's (@banerjeeamit) Get-TempDB function (https://github.com/amitmsft/SqlOnAzureVM/blob/master/Get-TempdbFiles.ps1)

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Test-DbaTempDbConfiguration

        .EXAMPLE
            Test-DbaTempDbConfiguration -SqlInstance localhost

            Checks tempdb on the localhost machine.

        .EXAMPLE
            Test-DbaTempDbConfiguration -SqlInstance localhost | Select-Object *

            Checks tempdb on the localhost machine. All rest results are shown.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Detailed,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed

        $result = @()
    }
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            #test for TF 1118
            if ($server.VersionMajor -ge 13) {
                $notes = 'SQL Server 2016 has this functionality enabled by default'
                # DBA May have changed setting. May need to check.
                $value = [PSCustomObject]@{
                    ComputerName   = $server.NetName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Rule           = 'TF 1118 Enabled'
                    Recommended    = $true
                    CurrentSetting = $true
                }
            }
            else {
                $sql = "DBCC TRACEON (3604);DBCC TRACESTATUS(-1)"
                $tfCheck = $server.Databases['tempdb'].Query($sql)
                $notes = 'KB328551 describes how TF 1118 can benefit performance.'

                $value = [PSCustomObject]@{
                    ComputerName   = $server.NetName
                    InstanceName   = $server.ServiceName
                    SqlInstance    = $server.DomainInstanceName
                    Rule           = 'TF 1118 Enabled'
                    Recommended    = $true
                    CurrentSetting = ($tfCheck.TraceFlag -join ',').Contains('1118')
                }
            }

            if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
                $isBestPractice = $false
            }
            else {
                $isBestPractice = $true
            }

            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name IsBestPractice -Value $isBestPractice
            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name Notes -Value $notes
            $result += $value
            Write-Message -Level Verbose -Message "TF 1118 evaluated"

            #get files and log files
            $tempdbFiles = Get-DbaDatabaseFile -SqlInstance $server -Database tempdb
            [array]$dataFiles = $tempdbFiles | Where-Object Type -ne 1
            $logFiles = $tempdbFiles | Where-Object Type -eq 1
            Write-Message -Level Verbose -Message "TempDB file objects gathered"

            $value = [PSCustomObject]@{
                ComputerName   = $server.NetName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Count'
                Recommended    = [Math]::Min(8, $server.Processors)
                CurrentSetting = $dataFiles.Count
            }

            if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
                $isBestPractice = $false
            }
            else {
                $isBestPractice = $true
            }

            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name IsBestPractice -Value $isBestPractice
            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name Notes -Value 'Microsoft recommends that the number of tempdb data files is equal to the number of logical cores up to 8.'
            $result += $value

            Write-Message -Level Verbose -Message "File counts evaluated."

            #test file growth
            $percData = $dataFiles | Where-Object GrowthType -ne 'KB' | Measure-Object
            $percLog = $logFiles  | Where-Object GrowthType -ne 'KB' | Measure-Object

            $totalCount = $percData.Count + $percLog.Count
            if ($totalCount -gt 0) {
                $totalCount = $true
            }
            else {
                $totalCount = $false
            }

            $value = [PSCustomObject]@{
                ComputerName   = $server.NetName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Growth in Percent'
                Recommended    = $false
                CurrentSetting = $totalCount
            }

            if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
                $isBestPractice = $false
            }
            else {
                $isBestPractice = $true
            }

            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name IsBestPractice -Value $isBestPractice
            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name Notes -Value 'Set file growth to explicit values, not by percent.'
            $result += $value

            Write-Message -Level Verbose -Message "File growth settings evaluated."
            #test file Location

            $cdata = ($dataFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count + ($logFiles | Where-Object PhysicalName -like 'C:*' | Measure-Object).Count
            if ($cdata -gt 0) {
                $cdata = $true
            }
            else {
                $cdata = $false
            }

            $value = [PSCustomObject]@{
                ComputerName   = $server.NetName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File Location'
                Recommended    = $false
                CurrentSetting = $cdata
            }

            if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
                $isBestPractice = $false
            }
            else {
                $isBestPractice = $true
            }

            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name IsBestPractice -Value $isBestPractice
            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name Notes -Value "Do not place your tempdb files on C:\."
            $result += $value

            Write-Message -Level Verbose -Message "File locations evaluated."

            #Test growth limits
            $growthLimits = ($dataFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count + ($logFiles | Where-Object MaxSize -gt 0 | Measure-Object).Count
            if ($growthLimits -gt 0) {
                $growthLimits = $true
            }
            else {
                $growthLimits = $false
            }

            $value = [PSCustomObject]@{
                ComputerName   = $server.NetName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                Rule           = 'File MaxSize Set'
                Recommended    = $false
                CurrentSetting = $growthLimits
            }

            if ($value.Recommended -ne $value.CurrentSetting -and $null -ne $value.Recommended) {
                $isBestPractice = $false
            }
            else {
                $isBestPractice = $true
            }

            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name IsBestPractice -Value $isBestPractice
            Add-Member -Force -InputObject $value -MemberType NoteProperty -Name Notes -Value "Consider setting your tempdb files to unlimited growth."
            $result += $value

            Write-Message -Level Verbose -Message "MaxSize values evaluated."

            Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Rule, Recommended, IsBestPractice
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Test-SqlTempDbConfiguration
    }
}
