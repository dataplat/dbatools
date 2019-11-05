$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Build', 'Kb', 'MajorVersion', 'ServicePack', 'CumulativeUpdate', 'SqlInstance', 'SqlCredential', 'Update', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Unit Test" -Tags Unittest {
    $ModuleBase = (Get-Module -Name dbatools | Where-Object ModuleBase -notmatch net).ModuleBase
    $idxfile = "$ModuleBase\bin\dbatools-buildref-index.json"
    Context 'Validate data in json is correct' {
        It "the json file is there" {
            $result = Test-Path $idxfile
            $result | Should Be $true
        }
        It "the json can be parsed" {
            $IdxRef = Get-Content $idxfile -raw | ConvertFrom-Json
            $IdxRef | Should BeOfType System.Object
        }
    }
    Context 'Validate LastUpdated property' {
        $IdxRef = Get-Content $idxfile -raw | ConvertFrom-Json
        It "Has a proper LastUpdated property" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should BeOfType System.DateTime
        }
        It "LastUpdated is updated regularly (keeps everybody on their toes)" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should BeGreaterThan (Get-Date).AddDays(-45)
        }
        It "LastUpdated is not in the future" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should BeLessThan (Get-Date)
        }
    }
    Context 'Validate Data property' {
        $IdxRef = Get-Content $idxfile -raw | ConvertFrom-Json
        It "Data is a proper array" {
            $IdxRef.Data.Length | Should BeGreaterThan 100
        }
        It "Each Datum has a Version property" {
            $DataLength = $IdxRef.Data.Length
            $DataWithVersion = ($IdxRef.Data.Version | Where-Object { $_ }).Length
            $DataLength | Should Be $DataWithVersion
        }
        It "Each version is correctly parsable" {
            $Versions = $IdxRef.Data.Version | Where-Object { $_ }
            foreach ($ver in $Versions) {
                $splitted = $ver.split('.')
                $dots = $ver.split('.').Length - 1
                if ($dots -ne 2) {
                    if ($dots[0] -le 15) {
                        $dots | Should Be 3
                    } else {
                        $dots | Should Be 4
                    }
                }
                try {
                    $splitted | ForEach-Object { [convert]::ToInt32($_) }
                } catch {
                    # I know. But someone can find a method to output a custom message ?
                    $splitted -join '.' | Should Be "Composed by integers"
                }
            }
        }
        It "Versions are ordered, the way versions are ordered" {
            $Versions = $IdxRef.Data.Version | Where-Object { $_ }
            $Naturalized = $Versions | ForEach-Object {
                $splitted = $_.split('.') | ForEach-Object { [convert]::ToInt32($_) }
                "$($splitted[0].toString('00'))$($splitted[1].toString('00'))$($splitted[2].toString('0000'))"
            }
            $SortedVersions = $Naturalized | Sort-Object
            ($SortedVersions -join ",") | Should Be ($Naturalized -join ",")
        }
        It "Names are at least 8" {
            $Names = $IdxRef.Data.Name | Where-Object { $_ }
            $Names.Length | Should BeGreaterThan 7
        }
    }
    # These are groups by major release (aka "Name")
    $IdxRef = Get-Content $idxfile -Raw | ConvertFrom-Json
    $Groups = @{ }
    $OrderedKeys = @()
    foreach ($el in $IdxRef.Data) {
        $ver = $el.Version.Split('.')[0 .. 1] -join '.'
        if (!($Groups.ContainsKey($ver))) {
            $Groups[$ver] = New-Object System.Collections.ArrayList
            $OrderedKeys += $ver
        }
        $null = $Groups[$ver].Add($el)
    }
    foreach ($g in $OrderedKeys) {
        $Versions = $Groups[$g]
        Context "Properties Check, for major release $g" {
            It "has the first element with a Name" {
                $Versions[0].Name | Should BeLike "20*"
            }
            It "No multiple Names around" {
                ($Versions.Name | Where-Object { $_ }).Count | Should Be 1
            }
            It "has a single version tagged as RTM" {
                ($Versions.SP -eq 'RTM').Count | Should Be 1
            }
            It "SP Property is formatted correctly" {
                $Versions.SP | Where-Object { $_ } | Should Match '^RTM$|^SP[\d]+$|^RC'
            }
            It "CU Property is formatted correctly" {
                $CUMatch = $Versions.CU | Where-Object { $_ }
                if ($CUMatch) {
                    $CUMatch | Should Match '^CU[\d]+$'
                }
            }
            It "SPs are ordered correctly" {
                $SPs = $Versions.SP | Where-Object { $_ }
                ($SPs | Select-Object -First 1) | Should BeIn 'RTM', 'RC'
                $ActualSPs = $SPs | Where-Object { $_ -match '^SP[\d]+$' }
                $OrderedActualSPs = $ActualSPs | Sort-Object
                ($ActualSPs -join ',') | Should Be ($OrderedActualSPs -join ',')
            }
            # see https://github.com/sqlcollaborative/dbatools/pull/2466
            It "KBList has only numbers on it" {
                $NotNumbers = $Versions.KBList | Where-Object { $_ } | Where-Object { $_ -notmatch '^[\d]+$' }
                if ($NotNumbers.Count -ne 0) {
                    foreach ($Nn in $NotNumbers) {
                        $Nn | Should Be "Composed by integers"
                    }
                }
            }
        }
    }
}

Describe "$commandname Integration Tests" -Tags 'IntegrationTests' {
    Context "Test retrieving version from instances" {
        $results = Get-DbaBuildReference -SqlInstance $script:instance1, $script:instance2
        It "Should return an exact match" {
            $results | Should -Not -BeNullOrEmpty
            foreach ($r in $results) {
                $r.MatchType | Should Be "Exact"
                $buildMatch = Get-DbaBuildReference -Build $r.BuildLevel
                $buildMatch | Should -Not -BeNullOrEmpty
                foreach ($b in $buildMatch) {
                    $b.MatchType | Should Be "Exact"
                    $b.KBLevel | Should BeIn $r.KBLevel
                }
                $kbMatch = Get-DbaBuildReference -KB ($r.KBLevel | Select-Object -First 1)
                $kbMatch | Should -Not -BeNullOrEmpty
                foreach ($m in $kbMatch) {
                    $m.MatchType | Should Be "Exact"
                    $m.KBLevel | Should BeIn $r.KBLevel
                }
                $spLevel = $r.SPLevel | Where-Object { $_ -ne 'LATEST' }
                $versionMatch = Get-DbaBuildReference -MajorVersion $r.NameLevel -ServicePack $spLevel -CumulativeUpdate $r.CULevel
                $versionMatch | Should -Not -BeNullOrEmpty
                foreach ($v in $versionMatch) {
                    $v.MatchType | Should Be "Exact"
                    $v.NameLevel | Should Be $r.NameLevel
                    $spLevel | Should BeIn $v.SPLevel
                    $v.CULevel | Should Be $r.CULevel
                }
            }
        }
    }
}