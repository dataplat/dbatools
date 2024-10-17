param($ModuleName = 'dbatools')

Describe "New-DbaDacOption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDacOption
        }
        It "Should have Type as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Mandatory:$false
        }
        It "Should have Action as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Action -Type String -Mandatory:$false
        }
        It "Should have PublishXml as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter PublishXml -Type String -Mandatory:$false
        }
        It "Should have Property as a non-mandatory Hashtable parameter" {
            $CommandUnderTest | Should -HaveParameter Property -Type Hashtable -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $publishprofile = New-DbaDacProfile -SqlInstance $global:instance1 -Database whatever -Path C:\temp
        }
        AfterAll {
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }
        It "Returns dacpac export options" {
            New-DbaDacOption -Action Export | Should -Not -BeNullOrEmpty
        }
        It "Returns bacpac export options" {
            New-DbaDacOption -Action Export -Type Bacpac | Should -Not -BeNullOrEmpty
        }
        It "Returns dacpac publish options" {
            New-DbaDacOption -Action Publish | Should -Not -BeNullOrEmpty
        }
        It "Returns dacpac publish options from an xml" {
            New-DbaDacOption -Action Publish -PublishXml $publishprofile.FileName -EnableException | Should -Not -BeNullOrEmpty
        }
        It "Returns bacpac publish options" {
            New-DbaDacOption -Action Publish -Type Bacpac | Should -Not -BeNullOrEmpty
        }
        It "Properly sets a property value when specified" {
            (New-DbaDacOption -Action Export -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
            (New-DbaDacOption -Action Export -Type Bacpac -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
            (New-DbaDacOption -Action Publish -Property @{GenerateDeploymentReport = $true }).GenerateDeploymentReport | Should -BeTrue
            (New-DbaDacOption -Action Publish -Type Bacpac -Property @{CommandTimeout = 5 }).CommandTimeout | Should -Be 5
            $result = (New-DbaDacOption -Action Publish -Property @{
                    GenerateDeploymentReport = $true; DeployOptions = @{CommandTimeout = 5 }
                }
            )
            $result.GenerateDeploymentReport | Should -BeTrue
            $result.DeployOptions.CommandTimeout | Should -Be 5
        }
    }
}
