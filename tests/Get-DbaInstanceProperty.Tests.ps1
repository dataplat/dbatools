param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceProperty" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceProperty
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have InstanceProperty as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter InstanceProperty -Type Object[] -Mandatory:$false
        }
        It "Should have ExcludeInstanceProperty as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeInstanceProperty -Type Object[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaInstanceProperty -SqlInstance $global:instance2
        }
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'PropertyType', 'SqlInstance'
            ($results | Get-Member -MemberType NoteProperty).Name | Should -Be $ExpectedProps
        }
        It "Should return a valid build" {
            $build = $results | Where-Object { $_.Name -eq 'ResourceVersionString' } | Select-Object -ExpandProperty Value
            (Get-DbaBuild -Build $build).MatchType | Should -Be "Exact"
        }
        It "Should have DisableDefaultConstraintCheck set to false" {
            ($results | Where-Object { $_.Name -eq 'DisableDefaultConstraintCheck' }).Value | Should -Be $false
        }
        It "Should get the correct DefaultFile location" {
            $defaultFiles = Get-DbaDefaultPath -SqlInstance $global:instance2
            ($results | Where-Object { $_.Name -eq 'DefaultFile' }).Value | Should -BeLike "$($defaultFiles.Data)*"
        }
    }

    Context "Property filters work" {
        BeforeAll {
            $resultInclude = Get-DbaInstanceProperty -SqlInstance $global:instance2 -InstanceProperty DefaultFile
            $resultExclude = Get-DbaInstanceProperty -SqlInstance $global:instance2 -ExcludeInstanceProperty DefaultFile
        }
        It "Should only return DefaultFile property" {
            $resultInclude.Name | Should -Contain 'DefaultFile'
        }
        It "Should not contain DefaultFile property" {
            $resultExclude.Name | Should -Not -Contain 'DefaultFile'
        }
    }

    Context "Command can handle multiple instances" {
        It "Should have results for 2 instances" {
            $results = Get-DbaInstanceProperty -SqlInstance $global:instance1, $global:instance2
            ($results | Select-Object -Unique SqlInstance).Count | Should -Be 2
        }
    }
}
