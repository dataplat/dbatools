# Cleanup and Resource Management

## Temporary Files and Cleanup

- Create temporary test files/directories with unique names using Get-Random
- Always clean up temporary resources in AfterAll or AfterEach blocks

```powershell
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Create unique temp path for this test run
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory
    }

    AfterAll {
        # Always clean up temp files
        Remove-Item -Path $backupPath -Recurse
    }

    Context "When performing backups" {
        # test code here
    }
}
```

## Critical Instruction
ALL comments must be preserved exactly as they appear in the original code, including seemingly unrelated or end-of-file comments. Even comments that appear to be development notes or temporary must be kept. This is especially important for comments related to CI/CD systems like AppVeyor.

## Resource Management Guidelines
- Always track resources created during tests
- Use array variables to collect resources for cleanup
- Clean up in reverse order of creation when dependencies exist
- Handle cleanup failures gracefully with -ErrorAction SilentlyContinue when appropriate