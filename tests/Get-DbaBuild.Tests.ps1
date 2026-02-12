#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaBuild",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Build",
                "Kb",
                "MajorVersion",
                "ServicePack",
                "CumulativeUpdate",
                "SqlInstance",
                "SqlCredential",
                "Update",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    BeforeAll {
        $ModuleBase = (Get-Module -Name dbatools | Where-Object ModuleBase -NotMatch net).ModuleBase
        $idxfile = "$ModuleBase\bin\dbatools-buildref-index.json"
    }

    Context 'Validate data in json is correct' {
        It "the json file is there" {
            $result = Test-Path $idxfile
            $result | Should -Be $true
        }
        It "the json can be parsed" {
            $IdxRef = Get-Content $idxfile -Raw | ConvertFrom-Json
            $IdxRef | Should -BeOfType System.Object
        }
    }
    Context 'Validate LastUpdated property' {
        BeforeAll {
            $IdxRef = Get-Content $idxfile -Raw | ConvertFrom-Json
        }
        It "Has a proper LastUpdated property" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should -BeOfType System.DateTime
        }
        It "LastUpdated is updated regularly (keeps everybody on their toes)" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should -BeGreaterThan (Get-Date).AddDays(-45)
        }
        It "LastUpdated is not in the future" {
            $lastupdate = Get-Date -Date $IdxRef.LastUpdated
            $lastupdate | Should -BeLessThan (Get-Date)
        }
    }
    Context 'Validate Data property' {
        BeforeAll {
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
        }
        It "Data is a proper array" {
            $IdxRef.Data.Length | Should -BeGreaterThan 100
        }
        It "Each Datum has a Version property" {
            $DataLength = $IdxRef.Data.Length
            $DataWithVersion = ($IdxRef.Data.Version | Where-Object { $PSItem }).Length
            $DataLength | Should -Be $DataWithVersion
        }
        It "Each version is correctly parsable" {
            $Versions = $IdxRef.Data.Version | Where-Object { $PSItem }
            foreach ($ver in $Versions) {
                $splitted = $ver.split('.')
                $dots = $ver.split('.').Length - 1
                if ($dots -ne 2) {
                    if ($dots[0] -le 15) {
                        $dots | Should -Be 3
                    } else {
                        $dots | Should -Be 4
                    }
                }
                try {
                    $splitted | ForEach-Object { [convert]::ToInt32($PSItem) }
                } catch {
                    # I know. But someone can find a method to output a custom message ?
                    $splitted -join "." | Should -Be "Composed by integers"
                }
            }
        }
        It "Versions are ordered, the way versions are ordered" {
            $Versions = $IdxRef.Data.Version | Where-Object { $PSItem }
            $Naturalized = $Versions | ForEach-Object {
                $splitted = $PSItem.split(".") | ForEach-Object { [convert]::ToInt32($PSItem) }
                "$($splitted[0].toString('00'))$($splitted[1].toString('00'))$($splitted[2].toString('0000'))"
            }
            $SortedVersions = $Naturalized | Sort-Object
            ($SortedVersions -join ",") | Should -Be ($Naturalized -join ",")
        }
        It "Names are at least 8" {
            $Names = $IdxRef.Data.Name | Where-Object { $PSItem }
            $Names.Length | Should -BeGreaterThan 7
        }
    }
    Context "Params mutual exclusion" {
        It "Doesn't accept 'Build', 'Kb', 'SqlInstance" {
            { Get-DbaBuild -Build "10.0.1600" -Kb "4052908" -SqlInstance "localhost" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'Kb'" {
            { Get-DbaBuild -Build "10.0.1600" -Kb "4052908" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'SqlInstance'" {
            { Get-DbaBuild -Build "10.0.1600" -SqlInstance "localhost" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'SqlInstance'" {
            { Get-DbaBuild -Build "10.0.1600" -SqlInstance "localhost" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'MajorVersion'" {
            { Get-DbaBuild -Build "10.0.1600" -MajorVersion "2016" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'ServicePack'" {
            { Get-DbaBuild -Build "10.0.1600" -ServicePack "SP2" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'Build', 'CumulativeUpdate'" {
            { Get-DbaBuild -Build "10.0.1600" -CumulativeUpdate "CU2" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'ServicePack' without 'MajorVersion'" {
            { Get-DbaBuild -ServicePack "SP2" -EnableException -ErrorAction Stop } | Should -Throw
        }
        It "Doesn't accept 'CumulativeUpdate' without 'MajorVersion'" {
            { Get-DbaBuild -CumulativeUpdate "CU2" -EnableException -ErrorAction Stop } | Should -Throw
        }
    }
    Context "Passing just -Update works, see #6823" {
        It "works with -Update" {
            function Get-DbaBuildReferenceIndexOnline { }
            Mock Get-DbaBuildReferenceIndexOnline -MockWith { }
            Get-DbaBuild -Update -WarningVariable warnings 3>$null
            $warnings | Should -BeNullOrEmpty
        }
    }
    Context "Retired KBs" {
        It "Handles retired KBs" {
            $result = Get-DbaBuild -Build "13.0.5479"
            $result.Warning | Should -Be "This version has been officially retired by Microsoft"
        }
    }

    Context "Recognizes version 'aliases', see #8915" {
        It "works with versions with the minor being either not 0 or 50" {
            $result2016 = Get-DbaBuild -Build "13.3.6300"
            $result2016.Build | Should -Be "13.3.6300"
            $result2016.BuildLevel | Should -Be "13.0.6300"
            $result2016.MatchType | Should -Be "Exact"

            $result2008R2 = Get-DbaBuild -Build "10.53.6220"
            $result2008R2.Build | Should -Be "10.53.6220"
            $result2008R2.BuildLevel | Should -Be "10.50.6220"
            $result2008R2.MatchType | Should -Be "Exact"
        }
    }
    # These are groups by major release (aka "Name")
    Context "Properties Check for major releases" {
        BeforeAll {
            $OrderedKeys = $OrderedKeys
            $Groups = $Groups
        }

        foreach ($g in $OrderedKeys) {
            Context "Properties Check, for major release $g" {
                BeforeAll {
                    $Versions = $Groups[$g]
                }
                It "has the first element with a Name" {
                    $Versions[0].Name | Should -BeLike "20*"
                }
                It "No multiple Names around" {
                    ($Versions.Name | Where-Object { $PSItem }).Count | Should -Be 1
                }
                It "SP Property is formatted correctly" {
                    $Versions.SP | Where-Object { $PSItem } | Should -Match "^RTM$|^SP[\d]+$|^RC"
                }
                It "CU Property is formatted correctly" {
                    $CUMatch = $Versions.CU | Where-Object { $PSItem }
                    if ($CUMatch) {
                        $CUMatch | Should -Match "^CU[\d]+$"
                    }
                }
                It "SPs are ordered correctly" {
                    $SPs = $Versions.SP | Where-Object { $PSItem }
                    ($SPs | Select-Object -First 1) | Should -BeIn "RTM", "RC"
                    $ActualSPs = $SPs | Where-Object { $PSItem -match "^SP[\d]+$" }
                    $OrderedActualSPs = $ActualSPs | Sort-Object
                    ($ActualSPs -join ",") | Should -Be ($OrderedActualSPs -join ",")
                }
                # see https://github.com/dataplat/dbatools/pull/2466
                It "KBList has only numbers on it" {
                    $NotNumbers = $Versions.KBList | Where-Object { $PSItem } | Where-Object { $PSItem -notmatch "^[\d]+$" }
                    if ($NotNumbers.Count -ne 0) {
                        foreach ($Nn in $NotNumbers) {
                            $Nn | Should -Be "Composed by integers"
                        }
                    }
                }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "piping and params" {
        BeforeAll {
            $server1 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        }
        It "works when instances are piped" {
            $res = @($server1, $server2) | Get-DbaBuild
            $res.Count | Should -Be 2
        }
        It "doesn't work when passed both piped instances and, e.g., -Kb (params mutual exclusion)" {
            { @($server1, $server2) | Get-DbaBuild -Kb -EnableException } | Should -Throw
        }
    }
    Context "Test retrieving version from instances" {
        BeforeAll {
            $resultFromBuild = Get-DbaBuild -Build "13.0.6300"
        }

        It "Should return an exact match" {
            $results = Get-DbaBuild -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $results | Should -Not -BeNullOrEmpty
            foreach ($r in $results) {
                $r.MatchType | Should -Be "Exact"
                $buildMatch = Get-DbaBuild -Build $r.BuildLevel
                $buildMatch | Should -Not -BeNullOrEmpty
                foreach ($b in $buildMatch) {
                    $b.MatchType | Should -Be "Exact"
                    $b.KBLevel | Should -BeIn $r.KBLevel
                }
                if ($r.KBLevel) {
                    #can be a RTM which has no corresponding KB
                    $kbMatch = Get-DbaBuild -KB ($r.KBLevel | Select-Object -First 1)
                    $kbMatch | Should -Not -BeNullOrEmpty
                    foreach ($m in $kbMatch) {
                        $m.MatchType | Should -Be "Exact"
                        $m.KBLevel | Should -BeIn $r.KBLevel
                    }
                }
                $spLevel = $r.SPLevel | Where-Object { $PSItem -ne "LATEST" }
                $versionMatch = Get-DbaBuild -MajorVersion $r.NameLevel -ServicePack $spLevel -CumulativeUpdate $r.CULevel
                $versionMatch | Should -Not -BeNullOrEmpty
                foreach ($v in $versionMatch) {
                    $v.MatchType | Should -Be "Exact"
                    $v.NameLevel | Should -Be $r.NameLevel
                    $spLevel | Should -BeIn $v.SPLevel
                    $v.CULevel | Should -Be $r.CULevel
                }
            }
        }

        It "Returns output of the documented type from SqlInstance" {
            $results = Get-DbaBuild -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $results | Should -Not -BeNullOrEmpty
            $results[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties from SqlInstance query" {
            $results = Get-DbaBuild -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            $expectedProps = @("SqlInstance", "Build", "NameLevel", "SPLevel", "CULevel", "KBLevel", "BuildLevel", "SupportedUntil", "MatchType", "Warning")
            foreach ($prop in $expectedProps) {
                $results[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Returns output of the documented type from Build lookup" {
            $resultFromBuild | Should -Not -BeNullOrEmpty
            $resultFromBuild[0] | Should -BeOfType PSCustomObject
        }

        It "Excludes SqlInstance from default display when using -Build" {
            $defaultProps = $resultFromBuild[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Not -Contain "SqlInstance" -Because "SqlInstance should be excluded from default display when using -Build"
        }
    }
}