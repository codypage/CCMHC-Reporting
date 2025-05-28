-- =================================================================================
-- Author:         Cody Page
-- Create Date:    2025-05-23
-- Purpose:        Provides raw data for the AIMS Quality Measure Power BI report. This
--                 includes active clients on antipsychotic medications and their
--                 corresponding AIMS screening history.
--
-- Returns:        A single result set with all necessary data for Power BI calculations.
-- =================================================================================
IF OBJECT_ID('dbo.usp_GetAimsValidationReportData', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_GetAimsValidationReportData;
GO

CREATE PROCEDURE dbo.usp_GetAimsValidationReportData
    -- Measurement start date.
    @measurementDate DATE = '2025-05-12'
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- ============================================================================
        -- CTE 0: Define all medication status codes that are considered 'Active'
        -- ============================================================================
        WITH cte_ActiveMedicationStatus (StatusCode)
        AS
        (
            SELECT 'A'     UNION ALL SELECT 'C'     UNION ALL SELECT 'CC'    UNION ALL
            SELECT 'EC'    UNION ALL SELECT 'PC'    UNION ALL SELECT 'FC'    UNION ALL
            SELECT 'ECU'   UNION ALL SELECT 'PCU'   UNION ALL SELECT 'ECCF'  UNION ALL
            SELECT 'ECUCF' UNION ALL SELECT 'ECDP'  UNION ALL SELECT 'ECUDP' UNION ALL
            SELECT 'IPEC'  UNION ALL SELECT 'IPECU' UNION ALL SELECT 'IPECDP'UNION ALL
            SELECT 'IPECUDP'
        ),
        -- ============================================================================
        -- CTE 1: Define all known antipsychotic medication names
        -- ============================================================================
        cte_Antipsychotics (MedicationName)
        AS
        (
            SELECT 'Haloperidol'                UNION ALL SELECT 'Haldol'                 UNION ALL
            SELECT 'Fluphenazine'               UNION ALL SELECT 'Prolixin'               UNION ALL
            SELECT 'Perphenazine'               UNION ALL SELECT 'Trilafon'               UNION ALL
            SELECT 'Thiothixene'                UNION ALL SELECT 'Navane'                 UNION ALL
            SELECT 'Trifluoperazine'            UNION ALL SELECT 'Stelazine'              UNION ALL
            SELECT 'Pimozide'                   UNION ALL SELECT 'Orap'                   UNION ALL
            SELECT 'Loxapine'                   UNION ALL SELECT 'Loxitane'               UNION ALL
            SELECT 'Molindone'                  UNION ALL SELECT 'Moban'                  UNION ALL
            SELECT 'Chlorpromazine'             UNION ALL SELECT 'Thorazine'              UNION ALL
            SELECT 'Thioridazine'               UNION ALL SELECT 'Mellaril'               UNION ALL
            SELECT 'Mesoridazine'               UNION ALL SELECT 'Serentil'               UNION ALL
            SELECT 'Acetophenazine'             UNION ALL SELECT 'Tindal'                 UNION ALL
            SELECT 'Carphenazine'               UNION ALL SELECT 'Proketazine'            UNION ALL
            SELECT 'Clozapine'                  UNION ALL SELECT 'Clozaril'               UNION ALL
            SELECT 'Risperidone'                UNION ALL SELECT 'Risperdal'              UNION ALL
            SELECT 'Paliperidone'               UNION ALL SELECT 'Invega'                 UNION ALL
            SELECT 'Olanzapine'                 UNION ALL SELECT 'Zyprexa'                UNION ALL
            SELECT 'Quetiapine'                 UNION ALL SELECT 'Seroquel'               UNION ALL
            SELECT 'Ziprasidone'                UNION ALL SELECT 'Geodon'                 UNION ALL
            SELECT 'Aripiprazole'               UNION ALL SELECT 'Abilify'                UNION ALL
            SELECT 'Asenapine'                  UNION ALL SELECT 'Saphris'                UNION ALL
            SELECT 'Iloperidone'                UNION ALL SELECT 'Fanapt'                 UNION ALL
            SELECT 'Lurasidone'                 UNION ALL SELECT 'Latuda'                 UNION ALL
            SELECT 'Brexpiprazole'              UNION ALL SELECT 'Rexulti'                UNION ALL
            SELECT 'Cariprazine'                UNION ALL SELECT 'Vraylar'                UNION ALL
            SELECT 'Lumateperone'               UNION ALL SELECT 'Caplyta'                UNION ALL
            SELECT 'Haloperidol decanoate'      UNION ALL SELECT 'Fluphenazine decanoate' UNION ALL
            SELECT 'Risperidone microspheres'   UNION ALL SELECT 'Risperdal Consta'       UNION ALL
            SELECT 'Paliperidone palmitate'     UNION ALL SELECT 'Invega Sustenna'        UNION ALL
            SELECT 'Invega Trinza'              UNION ALL SELECT 'Aripiprazole lauroxil'  UNION ALL
            SELECT 'Aristada'                   UNION ALL SELECT 'Aripiprazole monohydrate' UNION ALL
            SELECT 'Abilify Maintena'           UNION ALL SELECT 'Olanzapine pamoate'     UNION ALL
            SELECT 'Zyprexa Relprevv'
        ),
        -- ============================================================================
        -- CTE 2: Get the most recent antipsychotic medication episode for active clients
        -- ============================================================================
        cte_ClientMedicationEpisode
        AS
        (
            SELECT
                -- Dimension: Client unique identifier
                c.client_id,
                -- Dimension: Client first name
                c.first_name,
                -- Dimension: Client last name
                c.last_name,
                -- Dimension: Name of the antipsychotic medication
                m.medication,
                -- Dimension: Start date of the medication episode
                m.start_date,
                -- Dimension: Discontinuation date of the medication episode
                m.disc_date,
                -- Dimension: Full name of the prescribing provider
                ISNULL(emp.first_name + ' ' + emp.last_name, 'Not Assigned') AS PrescriberName,
                -- Fact: Row number to identify the latest medication episode per client
                ROW_NUMBER() OVER (PARTITION BY c.client_id ORDER BY m.start_date DESC, m.medication DESC) AS EpisodeSequence
            FROM
                dbo.Clients AS c
            INNER JOIN
                dbo.Meds AS m ON c.client_id = m.client_id
            INNER JOIN
                cte_Antipsychotics AS a ON LOWER(m.medication) LIKE '%' + LOWER(a.MedicationName) + '%'
            INNER JOIN -- Filter for medications with an explicitly active status code
                cte_ActiveMedicationStatus AS ams ON m.rx_status = ams.StatusCode
            LEFT JOIN
                dbo.Employees AS emp ON m.provider_id_int = emp.emp_id
            WHERE
                -- Client must be active in the system
                c.client_status = 'Active'
                -- The medication period must be active as of the measurement date
                AND m.start_date <= @measurementDate
                AND (m.disc_date IS NULL OR m.disc_date > @measurementDate)
                -- Filter out test client records
                AND LOWER(c.first_name) NOT LIKE '%test%'
                AND LOWER(c.last_name) NOT LIKE '%test%'
                AND (emp.emp_id IS NULL OR (LOWER(emp.first_name) NOT LIKE '%test%' AND LOWER(emp.last_name) NOT LIKE '%test%'))
        ),
        -- ============================================================================
        -- CTE 3: Join medication episode with the latest AIMS screening data
        -- ============================================================================
        cte_ClientAimsData
        AS
        (
            SELECT
                -- Dimension: Client unique identifier
                cm.client_id,
                -- Dimension: Client first name
                cm.first_name,
                -- Dimension: Client last name
                cm.last_name,
                -- Dimension: Name of the antipsychotic medication
                cm.medication,
                -- Dimension: Start date of the current medication episode
                cm.start_date AS MedicationStartDate,
                -- Dimension: End date of the current medication episode
                cm.disc_date AS MedicationEndDate,
                -- Dimension: Full name of the prescribing provider
                cm.PrescriberName,
                -- Dimension: Date of the most recent AIMS screening
                ce.date12 AS AimScreeningDate,
                -- Fact: The numeric score from the most recent AIMS screening
                ce.num19 AS AimsScore,
                -- Dimension: Categorization of risk based on AIMS screening status
                CASE
                    WHEN ce.date12 IS NULL THEN 'No AIMS Since AP Start'
                    WHEN ce.date12 < DATEADD(DAY, -180, @measurementDate) THEN 'Routine AIMS Overdue'
                    ELSE 'Current'
                END AS RiskBucket,
                -- Dimension: Detailed reason for the alert or status
                CASE
                    WHEN ce.date12 IS NULL THEN 'No AIMS on record since current AP episode started on ' + CONVERT(VARCHAR, cm.start_date, 101)
                    WHEN ce.date12 < DATEADD(DAY, -180, @measurementDate)
                        THEN 'Last AIMS (' + CONVERT(VARCHAR, ce.date12, 101) + ') is >180 days prior to ' + CONVERT(VARCHAR, @measurementDate, 101)
                    ELSE 'AIMS screening is current'
                END AS AlertReason,
                -- Dimension: The date used for all calculations in this report
                @measurementDate AS MeasurementDate
            FROM
                cte_ClientMedicationEpisode AS cm
            LEFT JOIN
                dbo.ClientsExt AS ce ON cm.client_id = ce.client_id
                -- Ensure AIMS screening is on or before the measurement date and after the medication start date
                AND ce.date12 <= @measurementDate
                AND ce.date12 >= cm.start_date
            WHERE
                cm.EpisodeSequence = 1 -- Only include the most recent medication episode
        )
        -- ============================================================================
        -- Final Result Set: Return all raw data with calculated flags for Power BI
        -- ============================================================================
        SELECT
            -- Dimension: Client unique identifier
            cad.client_id,
            -- Dimension: Client first name
            cad.first_name,
            -- Dimension: Client last name
            cad.last_name,
            -- Dimension: Name of the antipsychotic medication
            cad.medication,
            -- Dimension: Start date of the current medication episode
            cad.MedicationStartDate,
            -- Dimension: End date of the current medication episode
            cad.MedicationEndDate,
            -- Dimension: Full name of the prescribing provider
            cad.PrescriberName,
            -- Dimension: Date of the most recent AIMS screening
            cad.AimScreeningDate,
            -- Fact: The numeric score from the most recent AIMS screening
            cad.AimsScore,
            -- Dimension: Categorization of risk based on AIMS screening status
            cad.RiskBucket,
            -- Dimension: Detailed reason for the alert or status
            cad.AlertReason,
            -- Dimension: The date used for all calculations in this report
            cad.MeasurementDate,
            -- Fact: Binary flag indicating if an AIMS screening exists (1 for Yes, 0 for No)
            CASE WHEN cad.AimScreeningDate IS NOT NULL THEN 1 ELSE 0 END AS HasAimsScreening,
            -- Fact: Binary flag indicating if the AIMS score is high (>= 4)
            CASE WHEN cad.AimsScore >= 4 THEN 1 ELSE 0 END AS HasHighAimsScore
        FROM
            cte_ClientAimsData AS cad
        ORDER BY
            cad.RiskBucket,
            cad.PrescriberName,
            cad.client_id;

    END TRY
    BEGIN CATCH
        -- Capture error details.
        DECLARE @errorMessage   NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @errorSeverity  INT = ERROR_SEVERITY();
        DECLARE @errorState     INT = ERROR_STATE();

        -- Raise the error.
        RAISERROR(@errorMessage, @errorSeverity, @errorState);
    END CATCH;
END;
GO

-- ============================================================================
-- Example Execution:
-- ============================================================================
-- EXEC dbo.usp_GetAimsValidationReportData
--     @measurementDate = '2025-05-12';
-- GO