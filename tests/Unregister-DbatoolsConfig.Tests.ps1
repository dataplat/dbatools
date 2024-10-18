param($ModuleName = 'dbatools')

Describe "Unregister-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Unregister-DbatoolsConfig
        }
        It "Accepts ConfigurationItem as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigurationItem -Type Config[] -Mandatory:$false
        }
        It "Accepts FullName as a parameter" {
            $CommandUnderTest | Should -HaveParameter FullName -Type String[] -Mandatory:$false
        }
        It "Accepts Module as a parameter" {
            $CommandUnderTest | Should -HaveParameter Module -Type String -Mandatory:$false
        }
        It "Accepts Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String -Mandatory:$false
        }
        It "Accepts Scope as a parameter" {
            $CommandUnderTest | Should -HaveParameter Scope -Type Dataplat.Dbatools.Configuration.ConfigScope -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeAll {
            # Setup code for the tests
            # This is where you would typically create test configurations
        }

        It "Should unregister a configuration item" {
            # Test implementation
            # Example:
            # $testConfig = New-DbatoolsConfig -FullName "test.config" -Value "test"
            # Register-DbatoolsConfig $testConfig
            # Unregister-DbatoolsConfig -FullName "test.config"
            # Get-DbatoolsConfig -FullName "test.config" | Should -BeNullOrEmpty
        }

        It "Should unregister multiple configuration items" {
            # Test implementation
        }

        It "Should unregister configuration items by module" {
            # Test implementation
        }

        It "Should unregister configuration items by name" {
            # Test implementation
        }

        It "Should unregister configuration items by scope" {
            # Test implementation
        }
    }
}
