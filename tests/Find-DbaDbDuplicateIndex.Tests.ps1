param($ModuleName = 'dbatools')

Describe "Find-DbaDbDuplicateIndex" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Find-DbaDbDuplicateIndex
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[]
        }
        It "Should have IncludeOverlapping as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeOverlapping -Type SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $sql = "CREATE DATABASE [dbatools_dupeindex]"
            $server.Query($sql)
            $sql = @"
CREATE TABLE [dbatools_dupeindex].[dbo].[WABehaviorEvent](
    [BehaviorEventId] [smallint] NOT NULL,
    [ClickType] [nvarchar](50) NOT NULL,
    [Description] [nvarchar](512) NOT NULL,
    [BehaviorClassId] [tinyint] NOT NULL,
 CONSTRAINT [PK_WABehaviorEvent_BehaviorEventId] PRIMARY KEY CLUSTERED
(
    [BehaviorEventId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
UNIQUE NONCLUSTERED
(
    [ClickType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

CREATE UNIQUE NONCLUSTERED INDEX [IX_WABehaviorEvent_ClickType] ON [dbatools_dupeindex].[dbo].[WABehaviorEvent]
(
    [ClickType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

ALTER TABLE [dbatools_dupeindex].[dbo].[WABehaviorEvent] ADD UNIQUE NONCLUSTERED
(
    [ClickType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
"@
            $server.Query($sql)
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance1 -Database dbatools_dupeindex -Confirm:$false
        }

        It "Returns at least two results" {
            $results = Find-DbaDbDuplicateIndex -SqlInstance $script:instance1 -Database dbatools_dupeindex
            $results.Count | Should -BeGreaterOrEqual 2
        }
    }
}
