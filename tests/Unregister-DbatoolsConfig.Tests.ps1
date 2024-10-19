param($ModuleName = 'dbatools')

Describe "Unregister-DbatoolsConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Unregister-DbatoolsConfig
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ConfigurationItem",
                "FullName",
                "Module",
                "Name",
                "Scope"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
