# Test Structure Directive

## DESCRIBE BLOCKS

Replace all Describe block names with `$CommandName` variable.

Add appropriate tags to every Describe block (`-Tag UnitTests` or `-Tag IntegrationTests`).

Remove all `-ForEach` parameters from any test blocks.

```powershell
Describe $CommandName -Tag UnitTests {
    # tests here
}
```

## CONTEXT BLOCKS

Rewrite Context block names to describe specific scenarios or states using clear, descriptive language.

Examples: "When getting all databases", "When database is offline"

## TEST CODE ORGANIZATION

Move all setup code into `BeforeAll` or `BeforeEach` blocks.

Move all cleanup code into `AfterAll` or `AfterEach` blocks.

Move all test assertions into `It` blocks.

Remove all loose code from `Describe` or `Context` blocks.

Add EnableException parameter handling in BeforeAll/AfterAll for integration tests:

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