$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Test" -Tags Unittest {
    $ModuleBase = (Get-Module -Name dbatools).ModuleBase
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
            $lastupdate | Should BeGreaterThan (Get-Date).AddDays(-90)
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
                    $dots | Should Be 2
                }
                try {
                    $splitted | Foreach-Object { [convert]::ToInt32($_) }
                }
                catch {
                    # I know. But someone can find a method to output a custom message ?
                    $splitted -join '.' | Should Be "Composed by integers"
                }
            }
        }
        It "Versions are ordered, the way versions are ordered" {
            $Versions = $IdxRef.Data.Version | Where-Object { $_ }
            $Naturalized = $Versions | Foreach-Object {
                $splitted = $_.split('.') | Foreach-Object { [convert]::ToInt32($_) }
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
    $IdxRef = Get-Content $idxfile -raw | ConvertFrom-Json
    $Groups = @{ }
    $OrderedKeys = @()
    foreach ($el in $IdxRef.Data) {
        $ver = $el.Version.split('.')[0 .. 1] -join '.'
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
            It "has a single version tagged as LATEST" {
                ($Versions.SP -eq 'LATEST').Count | Should Be 1
            }
            It "SP Property is formatted correctly" {
                $Versions.SP | Where-Object { $_ } | Should Match '^RTM$|^LATEST$|^SP[\d]+$'
            }
            It "CU Property is formatted correctly" {
                $CUMatch = $Versions.CU | Where-Object { $_ }
                if ($CUMatch) {
                    $CUMatch | Should Match '^CU[\d]+$'
                }
            }
            It "SPs are ordered correctly" {
                $SPs = $Versions.SP | Where-Object { $_ }
                $SPs[0] | Should Be 'RTM'
                $SPs[-1] | Should Be 'LATEST'
                $ActualSPs = $SPs | Where-Object { $_ -match '^SP[\d]+$' }
                $OrderedActualSPs = $ActualSPs | Sort-Object
                ($ActualSPs -join ',') | Should Be ($OrderedActualSPs -join ',')
            }
            It "LATEST is on PAR with a SP" {
                $LATEST = $Versions | Where-Object SP -contains "LATEST"
                $LATEST.SP.Count | Should Be 2
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

Describe "$commandname Integration Tests" -Tags IntegrationTests {
    Context "Test retrieving version from instances" {
        $results = Get-DbaSqlBuildReference -SqlInstance $script:instance1, $script:instance2
        It "Should return an exact match" {
            foreach ($r in $results) {
                $r.MatchType | Should Be "Exact"
            }
        }
    }
}
