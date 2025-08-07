# Cleanup and Resource Management Directive

## TEMPORARY FILE HANDLING

Replace all temporary file/directory creation with unique names using Get-Random pattern.

Add cleanup code to AfterAll or AfterEach blocks for every temporary resource:

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

## RESOURCE TRACKING

Add array variables to collect all resources created during tests for cleanup tracking.

Implement cleanup in reverse order of creation when dependencies exist.

Add -ErrorAction SilentlyContinue to cleanup operations to handle failures gracefully.

Ensure every resource created in BeforeAll/BeforeEach has corresponding cleanup in AfterAll/AfterEach.