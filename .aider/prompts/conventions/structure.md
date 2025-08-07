# Test Structure

## Describe Blocks
- Use the `$CommandName` variable for Describe block names
- Include appropriate tags (`-Tag UnitTests` or `-Tag IntegrationTests`)
- **Never use `-ForEach` parameter on any test blocks**

```powershell
Describe $CommandName -Tag UnitTests {
    # tests here
}
```

## Context Blocks
- Describe specific scenarios or states
- Use clear, descriptive names that explain the test scenario
- Example: "When getting all databases", "When database is offline"

## Test Code Placement
- All setup code goes in `BeforeAll` or `BeforeEach` blocks
- All cleanup code goes in `AfterAll` or `AfterEach` blocks
- All test assertions go in `It` blocks
- No loose code in `Describe` or `Context` blocks
- Set and remove EnableException in BeforeAll/AfterAll for integration tests

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
        $filesToRemove = @()
        # setup code here
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
        Remove-Item -Path $filesToRemove -ErrorAction SilentlyContinue
    }

    Context "When getting all databases" {
        BeforeAll {
            $results = Get-DbaDatabase
        }

        It "Returns results" {
            $results | Should -Not -BeNullOrEmpty
        }
    }
}
```