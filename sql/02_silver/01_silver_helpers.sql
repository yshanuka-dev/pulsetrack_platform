-- ============================================================================
-- PulseTrack Silver Layer: Cleansing Helpers & Parser Functions
-- Schema: pulsetrack_silver
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pulsetrack_silver;
SET search_path TO pulsetrack_silver;

-- Robust Money Parser Function: strips $, USD, commas; converts N/A to NULL
CREATE OR REPLACE FUNCTION parse_money(raw_val TEXT)
RETURNS NUMERIC AS $$
DECLARE
    cleaned TEXT;
BEGIN
    IF raw_val IS NULL OR TRIM(raw_val) IN ('', 'N/A', 'null', 'None') THEN
        RETURN NULL;
    END IF;
    
    cleaned := REGEXP_REPLACE(raw_val, '[$,\s]|USD|US\$', '', 'gi');
    
    -- Handle remaining invalid strings
    BEGIN
        RETURN cleaned::NUMERIC;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Robust Timestamp Parser: handles ISO, epoch, US slash, dash, and textual month dates
CREATE OR REPLACE FUNCTION parse_timestamp_utc(raw_val TEXT)
RETURNS TIMESTAMPTZ AS $$
DECLARE
    cleaned TEXT;
BEGIN
    IF raw_val IS NULL OR TRIM(raw_val) IN ('', 'N/A', 'null', 'None') THEN
        RETURN NULL;
    END IF;

    cleaned := TRIM(raw_val);
    
    -- Check if numeric epoch (10 digits = seconds, 13 digits = millis)
    IF cleaned ~ '^[0-9]{10}$' THEN
        RETURN to_timestamp(cleaned::BIGINT);
    ELSIF cleaned ~ '^[0-9]{13}$' THEN
        RETURN to_timestamp(cleaned::BIGINT / 1000.0);
    END IF;

    -- Strip bogus 'EST', 'UTC', or zone suffix text if causing parse errors
    cleaned := REGEXP_REPLACE(cleaned, '\s+EST$', '', 'i');

    -- Try standard ISO/PostgreSQL casting
    BEGIN
        RETURN cleaned::TIMESTAMPTZ;
    EXCEPTION WHEN OTHERS THEN
        -- Try MM/DD/YYYY HH24:MI:SS
        BEGIN
            RETURN to_timestamp(cleaned, 'MM/DD/YYYY HH24:MI:SS');
        EXCEPTION WHEN OTHERS THEN
            -- Try MM/DD/YYYY HH24:MI
            BEGIN
                RETURN to_timestamp(cleaned, 'MM/DD/YYYY HH24:MI');
            EXCEPTION WHEN OTHERS THEN
                -- Try MM/DD/YYYY
                BEGIN
                    RETURN to_timestamp(cleaned, 'MM/DD/YYYY');
                EXCEPTION WHEN OTHERS THEN
                    -- Try Mon DD, YYYY (e.g. Nov 05, 2025)
                    BEGIN
                        RETURN to_timestamp(cleaned, 'Mon DD, YYYY');
                    EXCEPTION WHEN OTHERS THEN
                        -- Try DD-MM-YYYY
                        BEGIN
                            RETURN to_timestamp(cleaned, 'DD-MM-YYYY');
                        EXCEPTION WHEN OTHERS THEN
                            RETURN NULL;
                        END;
                    END;
                END;
            END;
        END;
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
