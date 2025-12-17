


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."app_role" AS ENUM (
    'admin',
    'manager',
    'staff',
    'accounts',
    'hrms',
    'agent'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_handle_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = timezone('Asia/Kolkata'::text, now());
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."app_handle_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_booking_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.booking_id IS NULL THEN
    NEW.booking_id := generate_booking_id();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assign_booking_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_invoice_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.invoice_id IS NULL THEN
    -- Check if this is a GST or Non-GST invoice by examining GST amounts
    IF (COALESCE(NEW.gst_amount, 0) > 0 OR COALESCE(NEW.cgst_amount, 0) > 0 OR COALESCE(NEW.igst_amount, 0) > 0) THEN
      -- GST invoice
      NEW.invoice_id := generate_gst_invoice_id();
    ELSE
      -- Non-GST invoice
      NEW.invoice_id := generate_non_gst_invoice_id();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assign_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_lead_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.lead_id IS NULL THEN
    NEW.lead_id := generate_lead_id(NEW.name);
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assign_lead_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_package_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.package_id IS NULL THEN
    NEW.package_id := generate_package_id(NEW.category);
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assign_package_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."assign_task_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.task_id IS NULL OR NEW.task_id = '' THEN
    NEW.task_id := generate_task_id();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."assign_task_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_create_commission_record"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  staff_record_id UUID;
  commission_amt NUMERIC;
BEGIN
  -- Only process if booking status changed to confirmed
  IF NEW.booking_status = 'Confirmed' AND (OLD.booking_status IS NULL OR OLD.booking_status != 'Confirmed') THEN
    
    -- Get staff profile for the booking creator
    SELECT id INTO staff_record_id 
    FROM public.staff_profiles 
    WHERE user_id = NEW.created_by AND is_commission_eligible = true;
    
    IF staff_record_id IS NOT NULL THEN
      -- Calculate commission
      commission_amt := public.calculate_booking_commission(NEW.id, NEW.created_by);
      
      -- Create commission record
      INSERT INTO public.commission_records (
        staff_id, booking_id, commission_type, booking_amount, 
        commission_rate, commission_amount, created_by
      ) VALUES (
        staff_record_id, NEW.id, 'agent', NEW.final_price_with_gst,
        5.0, commission_amt, NEW.created_by
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_create_commission_record"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."backfill_branch_data"() RETURNS TABLE("table_name" "text", "records_updated" integer, "records_null" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  updated_count INT;
  null_count INT;
BEGIN
  UPDATE public.leads l
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE l.created_by = up.user_id
  AND l.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.leads WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'leads'::TEXT, updated_count, null_count;
  
  UPDATE public.bookings b
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE b.created_by = up.user_id
  AND b.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.bookings WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'bookings'::TEXT, updated_count, null_count;
  
  UPDATE public.tasks t
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE t.created_by = up.user_id
  AND t.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.tasks WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'tasks'::TEXT, updated_count, null_count;
  
  UPDATE public.invoices i
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE i.created_by = up.user_id
  AND i.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.invoices WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'invoices'::TEXT, updated_count, null_count;
  
  UPDATE public.quotations q
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE q.created_by = up.user_id
  AND q.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.quotations WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'quotations'::TEXT, updated_count, null_count;
  
  UPDATE public.expenses e
  SET branch_id = b.id
  FROM public.branches b
  WHERE e.branch = b.location
  AND e.branch_id IS NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.expenses WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'expenses'::TEXT, updated_count, null_count;
  
  UPDATE public.attendance_records ar
  SET branch_id = up.branch_id
  FROM public.user_profiles up
  WHERE ar.employee_id = up.user_id
  AND ar.branch_id IS NULL
  AND up.branch_id IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  SELECT COUNT(*) INTO null_count FROM public.attendance_records WHERE branch_id IS NULL;
  RETURN QUERY SELECT 'attendance_records'::TEXT, updated_count, null_count;
END;
$$;


ALTER FUNCTION "public"."backfill_branch_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."branch_migration_report"() RETURNS TABLE("table_name" "text", "total_records" bigint, "records_with_creator" bigint, "records_without_creator" bigint, "estimated_backfill" bigint)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    'leads'::TEXT,
    COUNT(*)::BIGINT as total,
    COUNT(*) FILTER (WHERE created_by IS NOT NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IN (
      SELECT user_id FROM public.user_profiles WHERE branch_id IS NOT NULL
    ))::BIGINT
  FROM public.leads;
  
  RETURN QUERY
  SELECT 
    'bookings'::TEXT,
    COUNT(*)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NOT NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IN (
      SELECT user_id FROM public.user_profiles WHERE branch_id IS NOT NULL
    ))::BIGINT
  FROM public.bookings;
  
  RETURN QUERY
  SELECT 
    'tasks'::TEXT,
    COUNT(*)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NOT NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IN (
      SELECT user_id FROM public.user_profiles WHERE branch_id IS NOT NULL
    ))::BIGINT
  FROM public.tasks;
  
  RETURN QUERY
  SELECT 
    'invoices'::TEXT,
    COUNT(*)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NOT NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IS NULL)::BIGINT,
    COUNT(*) FILTER (WHERE created_by IN (
      SELECT user_id FROM public.user_profiles WHERE branch_id IS NOT NULL
    ))::BIGINT
  FROM public.invoices;
END;
$$;


ALTER FUNCTION "public"."branch_migration_report"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_booking_commission"("booking_id" "uuid", "staff_user_id" "uuid") RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  booking_amount NUMERIC := 0;
  commission_rate NUMERIC := 5.0; -- Default 5%
  staff_record_id UUID;
BEGIN
  -- Get booking amount
  SELECT final_price_with_gst INTO booking_amount 
  FROM public.bookings 
  WHERE id = booking_id;
  
  -- Get staff profile ID
  SELECT id INTO staff_record_id 
  FROM public.staff_profiles 
  WHERE user_id = staff_user_id AND is_commission_eligible = true;
  
  -- Return calculated commission if staff is eligible
  IF staff_record_id IS NOT NULL AND booking_amount > 0 THEN
    RETURN (booking_amount * commission_rate / 100);
  END IF;
  
  RETURN 0;
END;
$$;


ALTER FUNCTION "public"."calculate_booking_commission"("booking_id" "uuid", "staff_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_all_users_consistency"() RETURNS TABLE("email" "text", "has_auth" boolean, "has_profile" boolean, "has_role" boolean, "is_consistent" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(up.email, au.email) as email,
    (au.id IS NOT NULL) as has_auth,
    (up.user_id IS NOT NULL) as has_profile,
    (ur.user_id IS NOT NULL) as has_role,
    (au.id IS NOT NULL AND up.user_id IS NOT NULL AND ur.user_id IS NOT NULL) as is_consistent
  FROM auth.users au
  FULL OUTER JOIN user_profiles up ON au.id = up.user_id  -- ✅ FIXED: Join on user_id instead of id
  LEFT JOIN user_roles ur ON up.user_id = ur.user_id
  ORDER BY email;
END;
$$;


ALTER FUNCTION "public"."check_all_users_consistency"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_submission_limit"("p_employee_id" "uuid", "p_date" "date") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  v_count := get_daily_submission_count(p_employee_id, p_date);
  RETURN v_count < 3;
END;
$$;


ALTER FUNCTION "public"."check_submission_limit"("p_employee_id" "uuid", "p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_orphaned_profiles"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  deleted_profiles INT;
  deleted_roles INT;
BEGIN
  -- Delete orphaned roles first
  DELETE FROM public.user_roles 
  WHERE NOT EXISTS (SELECT 1 FROM auth.users WHERE id = user_roles.user_id);
  GET DIAGNOSTICS deleted_roles = ROW_COUNT;
  
  -- Delete orphaned profiles
  DELETE FROM public.user_profiles 
  WHERE NOT EXISTS (SELECT 1 FROM auth.users WHERE id = user_profiles.id);
  GET DIAGNOSTICS deleted_profiles = ROW_COUNT;
  
  RAISE NOTICE '✓ Cleaned up % orphaned profile(s) and % orphaned role(s)', deleted_profiles, deleted_roles;
END;
$$;


ALTER FUNCTION "public"."cleanup_orphaned_profiles"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_orphaned_profiles"() IS 'Cleans up orphaned profiles and roles that have no corresponding auth.users entry';



CREATE OR REPLACE FUNCTION "public"."cleanup_user_by_email"("user_email" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  profile_user_id UUID;
BEGIN
  -- Get user_id from profile (might be orphaned)
  SELECT id INTO profile_user_id FROM public.user_profiles WHERE email = user_email;
  
  IF profile_user_id IS NOT NULL THEN
    -- Delete role
    DELETE FROM public.user_roles WHERE user_id = profile_user_id;
    
    -- Delete profile
    DELETE FROM public.user_profiles WHERE id = profile_user_id;
    
    -- Try to delete auth user if exists
    PERFORM auth.delete_user(profile_user_id);
    
    RAISE NOTICE '✓ Cleaned up all data for email: %', user_email;
  END IF;
END;
$$;


ALTER FUNCTION "public"."cleanup_user_by_email"("user_email" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cleanup_user_by_email"("user_email" "text") IS 'Comprehensively removes all data (profile, role, auth) for a specific email address';



CREATE OR REPLACE FUNCTION "public"."compute_attendance_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  hours_worked NUMERIC;
  shift_start_time TIME;
  shift_end_time TIME;
  grace_minutes INTEGER := 15;
BEGIN
  -- Update timestamp
  NEW.updated_at := now();
  
  -- Get user's assigned shift timing
  SELECT checkin_time, checkout_time INTO shift_start_time, shift_end_time
  FROM public.attendance_shifts
  WHERE user_id = NEW.employee_id AND active = true
  LIMIT 1;
  
  -- If no shift assigned, use default times
  IF shift_start_time IS NULL THEN
    shift_start_time := '09:00:00'::TIME;
  END IF;
  
  IF shift_end_time IS NULL THEN
    shift_end_time := '17:30:00'::TIME;
  END IF;
  
  -- Compute total hours if both checkin and checkout exist
  IF NEW.checkin_at IS NOT NULL AND NEW.checkout_at IS NOT NULL THEN
    NEW.total_hours := NEW.checkout_at - NEW.checkin_at;
    hours_worked := EXTRACT(EPOCH FROM NEW.total_hours) / 3600;
    
    -- Set status based on hours worked
    IF hours_worked < 4 THEN
      NEW.status := 'half_day';
    ELSE
      NEW.status := 'present';
    END IF;
  END IF;
  
  -- Check if late (checkin after shift start + grace period)
  IF NEW.checkin_at IS NOT NULL THEN
    IF (NEW.checkin_at::TIME) > (shift_start_time + (grace_minutes || ' minutes')::INTERVAL) THEN
      NEW.late_flag := true;
    END IF;
  END IF;
  
  -- Check early exit (checkout before expected end time)
  IF NEW.checkout_at IS NOT NULL THEN
    IF (NEW.checkout_at::TIME) < shift_end_time THEN
      NEW.early_exit_flag := true;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."compute_attendance_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."compute_kpi_scores"("emp_id" "uuid", "start_date" "date", "end_date" "date") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  task_total INTEGER := 0;
  task_completed INTEGER := 0;
  task_on_time INTEGER := 0;
  avg_quality NUMERIC := 0;
  attendance_days INTEGER := 0;
  present_days INTEGER := 0;
  task_completion_pct NUMERIC := 0;
  on_time_pct NUMERIC := 0;
  attendance_pct NUMERIC := 0;
  final_score NUMERIC := 0;
BEGIN
  -- Calculate task metrics
  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'Completed'),
         COUNT(*) FILTER (WHERE status = 'Completed' AND completion_at <= deadline),
         AVG(quality_rating) FILTER (WHERE quality_rating IS NOT NULL)
  INTO task_total, task_completed, task_on_time, avg_quality
  FROM tasks
  WHERE assigned_to = emp_id 
    AND created_at::DATE BETWEEN start_date AND end_date;
  
  -- Calculate attendance metrics
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE status IN ('present', 'half_day'))
  INTO attendance_days, present_days
  FROM attendance_records
  WHERE employee_id = emp_id
    AND attendance_date BETWEEN start_date AND end_date;
  
  -- Calculate percentages
  IF task_total > 0 THEN
    task_completion_pct := (task_completed::NUMERIC / task_total) * 100;
    on_time_pct := (task_on_time::NUMERIC / task_total) * 100;
  END IF;
  
  IF attendance_days > 0 THEN
    attendance_pct := (present_days::NUMERIC / attendance_days) * 100;
  END IF;
  
  -- Calculate final KPI score using weights
  final_score := (
    (task_completion_pct * 0.4) +
    (on_time_pct * 0.3) +
    (COALESCE(avg_quality, 0) * 20 * 0.2) + -- Convert 1-5 to percentage
    (attendance_pct * 0.1)
  );
  
  -- Insert or update KPI scores
  INSERT INTO kpi_scores (
    employee_id, period_start, period_end,
    task_completion_pct, on_time_completion_pct,
    task_quality_score, attendance_pct, final_score
  )
  VALUES (
    emp_id, start_date, end_date,
    task_completion_pct, on_time_pct,
    COALESCE(avg_quality, 0), attendance_pct, final_score
  )
  ON CONFLICT (employee_id, period_start, period_end)
  DO UPDATE SET
    task_completion_pct = EXCLUDED.task_completion_pct,
    on_time_completion_pct = EXCLUDED.on_time_completion_pct,
    task_quality_score = EXCLUDED.task_quality_score,
    attendance_pct = EXCLUDED.attendance_pct,
    final_score = EXCLUDED.final_score;
END;
$$;


ALTER FUNCTION "public"."compute_kpi_scores"("emp_id" "uuid", "start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_agent_commission_on_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  agent_profile_id UUID;
  agent_commission_rate NUMERIC;
  calculated_commission NUMERIC;
BEGIN
  -- Only proceed if referred_by_id exists
  IF NEW.referred_by_id IS NOT NULL THEN
    -- Get agent profile
    SELECT id, commission_rate INTO agent_profile_id, agent_commission_rate
    FROM agent_profiles
    WHERE user_id = NEW.referred_by_id AND is_active = true;
    
    IF agent_profile_id IS NOT NULL THEN
      -- Calculate commission
      calculated_commission := NEW.final_price_with_gst * (agent_commission_rate / 100);
      
      -- Insert commission record
      INSERT INTO commission_records (
        staff_id,
        booking_id,
        commission_type,
        booking_amount,
        commission_rate,
        commission_amount,
        earned_date,
        status,
        payout_status,
        created_by
      ) VALUES (
        agent_profile_id,
        NEW.id,
        'agent',
        NEW.final_price_with_gst,
        agent_commission_rate,
        calculated_commission,
        CURRENT_DATE,
        'pending',
        'pending',
        NEW.created_by
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_agent_commission_on_booking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_agent_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only create agent profile if role is 'agent'
  IF NEW.role = 'agent' THEN
    INSERT INTO public.agent_profiles (user_id, email, name, phone)
    VALUES (
      NEW.id,
      NEW.email,
      NEW.name,
      ''
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_agent_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_group_tour_capacity"("p_package_id" "uuid", "p_travel_date" "date", "p_booking_id" "uuid", "p_pax_count" integer, "p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_date_record RECORD;
  v_new_capacity INTEGER;
BEGIN
  SELECT * INTO v_date_record
  FROM public.group_tour_dates
  WHERE package_id = p_package_id 
    AND travel_date = p_travel_date
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Group tour date not found'
    );
  END IF;

  IF v_date_record.capacity_remaining < p_pax_count THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Insufficient capacity',
      'available', v_date_record.capacity_remaining,
      'requested', p_pax_count
    );
  END IF;

  v_new_capacity := v_date_record.capacity_remaining - p_pax_count;

  UPDATE public.group_tour_dates
  SET capacity_remaining = v_new_capacity,
      updated_at = now()
  WHERE id = v_date_record.id;

  INSERT INTO public.group_tour_capacity_audit (
    group_tour_date_id,
    booking_id,
    previous_capacity,
    new_capacity,
    pax_count,
    changed_by,
    reason
  ) VALUES (
    v_date_record.id,
    p_booking_id,
    v_date_record.capacity_remaining,
    v_new_capacity,
    p_pax_count,
    p_user_id,
    'Booking created'
  );

  RETURN json_build_object(
    'success', true,
    'group_tour_date_id', v_date_record.id,
    'previous_capacity', v_date_record.capacity_remaining,
    'new_capacity', v_new_capacity,
    'pax_count', p_pax_count
  );
END;
$$;


ALTER FUNCTION "public"."decrement_group_tour_capacity"("p_package_id" "uuid", "p_travel_date" "date", "p_booking_id" "uuid", "p_pax_count" integer, "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_booking_id"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_year INTEGER;
  sequence_num INTEGER;
  booking_id TEXT;
BEGIN
  current_year := EXTRACT(YEAR FROM now());
  
  -- Get and increment sequence for current year
  INSERT INTO booking_id_sequences (year, next_sequence)
  VALUES (current_year, 2)
  ON CONFLICT (year) 
  DO UPDATE SET next_sequence = booking_id_sequences.next_sequence + 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate booking ID: BK-2025-0001
  booking_id := 'BK-' || current_year || '-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN booking_id;
END;
$$;


ALTER FUNCTION "public"."generate_booking_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_cancellation_invoice_id"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  current_year INTEGER;
  seq_number INTEGER;
  new_id TEXT;
BEGIN
  current_year := EXTRACT(YEAR FROM CURRENT_DATE);
  
  INSERT INTO cancellation_invoice_sequences (year, next_sequence)
  VALUES (current_year, 1)
  ON CONFLICT (year) DO NOTHING;
  
  UPDATE cancellation_invoice_sequences
  SET next_sequence = next_sequence + 1
  WHERE year = current_year
  RETURNING next_sequence - 1 INTO seq_number;
  
  new_id := 'CINV-' || current_year || '-' || LPAD(seq_number::TEXT, 3, '0');
  
  RETURN new_id;
END;
$$;


ALTER FUNCTION "public"."generate_cancellation_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_employee_code"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_year INT;
  next_seq INT;
  employee_code TEXT;
BEGIN
  -- Get current year
  current_year := EXTRACT(YEAR FROM CURRENT_DATE);
  
  -- Get and increment the sequence for current year
  INSERT INTO public.employee_code_sequences (year, next_sequence)
  VALUES (current_year, 2)
  ON CONFLICT (year)
  DO UPDATE SET next_sequence = employee_code_sequences.next_sequence + 1
  RETURNING next_sequence - 1 INTO next_seq;
  
  -- Format: EMP-YYYY-NNNN (e.g., EMP-2025-0001)
  employee_code := 'EMP-' || current_year || '-' || LPAD(next_seq::TEXT, 4, '0');
  
  RETURN employee_code;
END;
$$;


ALTER FUNCTION "public"."generate_employee_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_gst_invoice_id"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  sequence_num INTEGER;
  invoice_id TEXT;
BEGIN
  -- Get and increment sequence for GST invoices
  UPDATE invoice_sequences 
  SET next_sequence = next_sequence + 1 
  WHERE id = 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate GST invoice ID: IN-STT-0001
  invoice_id := 'IN-STT-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN invoice_id;
END;
$$;


ALTER FUNCTION "public"."generate_gst_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invoice_id"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  sequence_num INTEGER;
  invoice_id TEXT;
BEGIN
  -- Get and increment sequence
  UPDATE invoice_sequences 
  SET next_sequence = next_sequence + 1 
  WHERE id = 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate invoice ID: IN-STT-0001
  invoice_id := 'IN-STT-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN invoice_id;
END;
$$;


ALTER FUNCTION "public"."generate_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_lead_id"("customer_name" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_year INTEGER;
  sequence_num INTEGER;
  name_prefix TEXT;
  lead_id TEXT;
BEGIN
  current_year := EXTRACT(YEAR FROM now());
  
  -- Extract first 3 letters from customer name (uppercase)
  name_prefix := UPPER(LEFT(REGEXP_REPLACE(customer_name, '[^A-Za-z]', '', 'g'), 3));
  
  -- Pad with 'XXX' if name is too short
  IF LENGTH(name_prefix) < 3 THEN
    name_prefix := RPAD(name_prefix, 3, 'X');
  END IF;
  
  -- Get and increment sequence for current year
  INSERT INTO lead_id_sequences (year, next_sequence)
  VALUES (current_year, 2)
  ON CONFLICT (year) 
  DO UPDATE SET next_sequence = lead_id_sequences.next_sequence + 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate lead ID: STT-AVI-001
  lead_id := 'STT-' || name_prefix || '-' || LPAD(sequence_num::TEXT, 3, '0');
  
  RETURN lead_id;
END;
$$;


ALTER FUNCTION "public"."generate_lead_id"("customer_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_non_gst_invoice_id"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  sequence_num INTEGER;
  invoice_id TEXT;
BEGIN
  -- Get and increment sequence for Non-GST invoices
  UPDATE invoice_non_gst_sequences 
  SET next_sequence = next_sequence + 1 
  WHERE id = 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate Non-GST invoice ID: IN-STN-0001
  invoice_id := 'IN-STN-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN invoice_id;
END;
$$;


ALTER FUNCTION "public"."generate_non_gst_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_package_id"("pkg_category" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  code_mapping TEXT;
  sequence_num INTEGER;
  package_id TEXT;
BEGIN
  -- Map category to code
  CASE pkg_category
    WHEN 'group' THEN code_mapping := 'GT';
    WHEN 'readymade' THEN code_mapping := 'RP';
    WHEN 'customize' THEN code_mapping := 'CZ';
    WHEN 'dmc' THEN code_mapping := 'DMC';
    ELSE RAISE EXCEPTION 'Invalid category: %', pkg_category;
  END CASE;

  -- Get and increment sequence
  UPDATE package_id_sequences 
  SET next_sequence = next_sequence + 1 
  WHERE category = pkg_category 
  RETURNING next_sequence - 1 INTO sequence_num;

  -- Generate package ID
  package_id := 'STT-' || code_mapping || '-' || LPAD(sequence_num::TEXT, 3, '0');
  
  RETURN package_id;
END;
$$;


ALTER FUNCTION "public"."generate_package_id"("pkg_category" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_receipt_number"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_year INTEGER;
  sequence_num INTEGER;
  receipt_number TEXT;
BEGIN
  current_year := EXTRACT(YEAR FROM now());
  
  -- Get and increment sequence for current year
  INSERT INTO receipt_sequences (year, next_sequence)
  VALUES (current_year, 2)
  ON CONFLICT (year) 
  DO UPDATE SET next_sequence = receipt_sequences.next_sequence + 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate receipt number: RCPT-2025-0001
  receipt_number := 'RCPT-' || current_year || '-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN receipt_number;
END;
$$;


ALTER FUNCTION "public"."generate_receipt_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_task_id"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  current_year INTEGER;
  sequence_num INTEGER;
  task_id TEXT;
BEGIN
  current_year := EXTRACT(YEAR FROM now());
  
  -- Get and increment sequence for current year
  INSERT INTO task_id_sequences (year, next_sequence)
  VALUES (current_year, 2)
  ON CONFLICT (year) 
  DO UPDATE SET next_sequence = task_id_sequences.next_sequence + 1
  RETURNING next_sequence - 1 INTO sequence_num;
  
  -- Generate task ID: TSK-2025-0001
  task_id := 'TSK-' || current_year || '-' || LPAD(sequence_num::TEXT, 4, '0');
  
  RETURN task_id;
END;
$$;


ALTER FUNCTION "public"."generate_task_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_daily_submission_count"("p_employee_id" "uuid", "p_date" "date") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*)
  INTO v_count
  FROM attendance_submissions
  WHERE employee_id = p_employee_id
    AND DATE(submitted_at) = p_date;
  
  RETURN COALESCE(v_count, 0);
END;
$$;


ALTER FUNCTION "public"."get_daily_submission_count"("p_employee_id" "uuid", "p_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_branch_id"("_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT branch_id
  FROM public.user_profiles
  WHERE user_id = _user_id
  LIMIT 1;
$$;


ALTER FUNCTION "public"."get_user_branch_id"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_branch_ids"("_user_id" "uuid") RETURNS "uuid"[]
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_role TEXT;
  user_branch_id UUID;
  branch_ids UUID[];
BEGIN
  SELECT role, branch_id INTO user_role, user_branch_id
  FROM public.user_profiles
  WHERE user_id = _user_id;
  
  IF user_role = 'admin' THEN
    SELECT ARRAY_AGG(id) INTO branch_ids
    FROM public.branches
    WHERE active = TRUE;
    RETURN COALESCE(branch_ids, ARRAY[]::UUID[]);
  END IF;
  
  IF user_branch_id IS NOT NULL THEN
    RETURN ARRAY[user_branch_id];
  END IF;
  
  RETURN ARRAY[]::UUID[];
END;
$$;


ALTER FUNCTION "public"."get_user_branch_ids"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_agent_role_assignment"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_profile user_profiles%ROWTYPE;
BEGIN
  -- Only proceed if role is 'agent'
  IF NEW.role = 'agent' THEN
    -- Get user profile data
    SELECT * INTO v_profile FROM user_profiles WHERE user_id = NEW.user_id;
    
    IF FOUND THEN
      -- Check if agent_profile already exists
      IF NOT EXISTS (SELECT 1 FROM agent_profiles WHERE user_id = NEW.user_id) THEN
        INSERT INTO agent_profiles (user_id, name, email, commission_rate, is_active)
        VALUES (NEW.user_id, v_profile.name, v_profile.email, 5.0, true);
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_agent_role_assignment"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Create user profile
  INSERT INTO public.user_profiles (user_id, name, email, role, created_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'role', 'staff'),
    NOW()
  )
  ON CONFLICT (user_id) DO NOTHING;
  
  -- Create user role
  INSERT INTO public.user_roles (user_id, role, created_at)
  VALUES (
    NEW.id,
    COALESCE((NEW.raw_user_meta_data->>'role')::app_role, 'staff'::app_role),
    NOW()
  )
  ON CONFLICT (user_id, role) DO NOTHING;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;


ALTER FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.user_profiles 
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_inside_geofence"("lat" numeric, "lng" numeric, "geofence_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  geofence_record office_geofences%ROWTYPE;
  distance_meters NUMERIC;
BEGIN
  -- Get geofence details
  SELECT * INTO geofence_record
  FROM office_geofences
  WHERE id = geofence_id AND active = true;
  
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  
  -- Calculate distance using Haversine formula (simplified)
  -- This is an approximation, for production use PostGIS
  distance_meters := (
    6371000 * acos(
      cos(radians(geofence_record.center_lat)) * 
      cos(radians(lat)) * 
      cos(radians(lng) - radians(geofence_record.center_lng)) + 
      sin(radians(geofence_record.center_lat)) * 
      sin(radians(lat))
    )
  );
  
  RETURN distance_meters <= geofence_record.radius_meters;
END;
$$;


ALTER FUNCTION "public"."is_inside_geofence"("lat" numeric, "lng" numeric, "geofence_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_manager"("_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_profiles
    WHERE user_id = _user_id
      AND role = 'manager'
  );
$$;


ALTER FUNCTION "public"."is_manager"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_task_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  action_type TEXT;
  meta_data JSONB := '{}';
  current_user_profile_id UUID;
BEGIN
  -- Get the user_profiles.id for the current auth user
  SELECT id INTO current_user_profile_id
  FROM user_profiles
  WHERE user_id = auth.uid();
  
  -- Skip logging if no profile found (shouldn't happen in normal flow)
  IF current_user_profile_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Determine action type based on trigger operation
  IF TG_OP = 'INSERT' THEN
    action_type := 'created';
    meta_data := jsonb_build_object(
      'task_id', NEW.task_id,
      'title', NEW.title,
      'assigned_to', NEW.assigned_to,
      'priority', NEW.priority
    );
  ELSIF TG_OP = 'UPDATE' THEN
    -- Check what changed
    IF OLD.status != NEW.status THEN
      action_type := 'status_changed';
      meta_data := jsonb_build_object(
        'old_status', OLD.status,
        'new_status', NEW.status
      );
    ELSIF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
      action_type := 'reassigned';
      meta_data := jsonb_build_object(
        'old_assignee', OLD.assigned_to,
        'new_assignee', NEW.assigned_to
      );
    ELSIF NEW.status = 'Completed' AND OLD.status != 'Completed' THEN
      action_type := 'completed';
      meta_data := jsonb_build_object(
        'completion_at', NEW.completion_at
      );
    ELSE
      action_type := 'updated';
    END IF;
  END IF;

  -- Insert activity log using user_profiles.id instead of auth.uid()
  INSERT INTO public.task_activity_log (task_id, action, meta, user_id)
  VALUES (NEW.id, action_type, meta_data, current_user_profile_id);

  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_task_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_admins"("notification_type" "text", "notification_title" "text", "notification_message" "text", "notification_data" "jsonb" DEFAULT '{}'::"jsonb", "reference_id" "uuid" DEFAULT NULL::"uuid", "created_by_user_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  admin_user_id UUID;
BEGIN
  -- Insert notification for all admin users
  FOR admin_user_id IN 
    SELECT id FROM user_profiles WHERE role = 'admin'
  LOOP
    INSERT INTO public.notifications (
      user_id, type, title, message, data, reference_id, created_by
    ) VALUES (
      admin_user_id, notification_type, notification_title, 
      notification_message, notification_data, reference_id, created_by_user_id
    );
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."notify_admins"("notification_type" "text", "notification_title" "text", "notification_message" "text", "notification_data" "jsonb", "reference_id" "uuid", "created_by_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM notify_admins(
    'new_booking',
    'New Booking Created',
    'A new booking "' || NEW.booking_id || '" has been created for ' || NEW.customer_name,
    jsonb_build_object(
      'booking_id', NEW.id,
      'booking_ref', NEW.booking_id,
      'customer_name', NEW.customer_name,
      'tour_package', NEW.tour_package_name,
      'amount', NEW.final_price_with_gst
    ),
    NEW.id,
    NEW.created_by
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_new_booking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_followup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  lead_name TEXT;
BEGIN
  -- Get lead name
  SELECT name INTO lead_name FROM leads WHERE id = NEW.lead_id;
  
  IF NEW.activity_type IN ('follow_up', 'call', 'email', 'meeting') THEN
    PERFORM notify_admins(
      'new_followup',
      'New Follow-up Activity',
      'A new ' || NEW.activity_type || ' activity has been created for lead "' || COALESCE(lead_name, 'Unknown') || '"',
      jsonb_build_object(
        'activity_id', NEW.id,
        'lead_id', NEW.lead_id,
        'lead_name', lead_name,
        'activity_type', NEW.activity_type,
        'description', NEW.description
      ),
      NEW.lead_id,
      NEW.created_by
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_new_followup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_lead"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM notify_admins(
    'new_lead',
    'New Lead Created',
    'A new lead "' || NEW.name || '" has been created from ' || COALESCE(NEW.source, 'Unknown source'),
    jsonb_build_object(
      'lead_id', NEW.id,
      'customer_name', NEW.name,
      'source', NEW.source,
      'destination', NEW.destination
    ),
    NEW.id,
    NEW.created_by
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."notify_new_lead"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."parse_human_date"("date_str" "text") RETURNS "date"
    LANGUAGE "plpgsql" IMMUTABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  date_str := regexp_replace(trim(date_str), '(\d+)(st|nd|rd|th)', '\1', 'g');
  RETURN to_date(date_str, 'DD Month YYYY');
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;


ALTER FUNCTION "public"."parse_human_date"("date_str" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_checkin"("lat" numeric, "lng" numeric, "device_id" "text" DEFAULT NULL::"text", "geofence_id" "uuid" DEFAULT NULL::"uuid", "photo_url" "text" DEFAULT NULL::"text", "accuracy_meters" numeric DEFAULT NULL::numeric) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_id UUID;
  attendance_id UUID;
  is_valid_location BOOLEAN := true;
  result JSON;
BEGIN
  user_id := auth.uid();
  
  IF user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Check geofence if provided
  IF geofence_id IS NOT NULL THEN
    is_valid_location := is_inside_geofence(lat, lng, geofence_id);
    IF NOT is_valid_location THEN
      RETURN json_build_object('success', false, 'error', 'Outside geofence area');
    END IF;
  END IF;
  
  -- Check if already checked in today
  IF EXISTS(
    SELECT 1 FROM attendance_records 
    WHERE employee_id = user_id 
      AND attendance_date = CURRENT_DATE
      AND checkin_at IS NOT NULL
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Already checked in today');
  END IF;
  
  -- Create or update attendance record
  INSERT INTO attendance_records (
    employee_id, attendance_date, checkin_at,
    checkin_lat, checkin_lng, checkin_source,
    geofence_id, photo_url, accuracy_meters
  )
  VALUES (
    user_id, CURRENT_DATE, now(),
    lat, lng, 'app',
    geofence_id, photo_url, accuracy_meters
  )
  ON CONFLICT (employee_id, attendance_date)
  DO UPDATE SET
    checkin_at = now(),
    checkin_lat = lat,
    checkin_lng = lng,
    checkin_source = 'app',
    geofence_id = EXCLUDED.geofence_id,
    photo_url = EXCLUDED.photo_url,
    accuracy_meters = EXCLUDED.accuracy_meters
  RETURNING id INTO attendance_id;
  
  -- Update device session if device_id provided
  IF device_id IS NOT NULL THEN
    INSERT INTO device_sessions (user_id, device_id, last_active)
    VALUES (user_id, device_id, now())
    ON CONFLICT (user_id, device_id)
    DO UPDATE SET last_active = now();
  END IF;
  
  result := json_build_object(
    'success', true,
    'attendance_id', attendance_id,
    'checkin_time', now(),
    'valid_location', is_valid_location
  );
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."rpc_checkin"("lat" numeric, "lng" numeric, "device_id" "text", "geofence_id" "uuid", "photo_url" "text", "accuracy_meters" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_checkout"("lat" numeric, "lng" numeric, "device_id" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_id UUID;
  attendance_record attendance_records%ROWTYPE;
  result JSON;
BEGIN
  user_id := auth.uid();
  
  IF user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Get today's attendance record
  SELECT * INTO attendance_record
  FROM attendance_records
  WHERE employee_id = user_id 
    AND attendance_date = CURRENT_DATE
    AND checkin_at IS NOT NULL;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'No check-in found for today');
  END IF;
  
  IF attendance_record.checkout_at IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'Already checked out today');
  END IF;
  
  -- Update with checkout details
  UPDATE attendance_records
  SET checkout_at = now(),
      checkout_lat = lat,
      checkout_lng = lng,
      checkout_source = 'app'
  WHERE id = attendance_record.id;
  
  -- Update device session if device_id provided
  IF device_id IS NOT NULL THEN
    INSERT INTO device_sessions (user_id, device_id, last_active)
    VALUES (user_id, device_id, now())
    ON CONFLICT (user_id, device_id)
    DO UPDATE SET last_active = now();
  END IF;
  
  result := json_build_object(
    'success', true,
    'attendance_id', attendance_record.id,
    'checkout_time', now()
  );
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."rpc_checkout"("lat" numeric, "lng" numeric, "device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rpc_get_attendance_summary"("emp_id" "uuid", "period_start" "date", "period_end" "date") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  present_days INTEGER := 0;
  half_days INTEGER := 0;
  absent_days INTEGER := 0;
  late_count INTEGER := 0;
  total_hours INTERVAL := INTERVAL '0 hours';
  overtime_hours INTERVAL := INTERVAL '0 hours';
  result JSON;
BEGIN
  SELECT 
    COUNT(*) FILTER (WHERE status = 'present'),
    COUNT(*) FILTER (WHERE status = 'half_day'),
    COUNT(*) FILTER (WHERE status = 'absent'),
    COUNT(*) FILTER (WHERE late_flag = true),
    COALESCE(SUM(total_hours), INTERVAL '0 hours'),
    COALESCE(SUM(CASE WHEN total_hours > INTERVAL '8 hours' THEN total_hours - INTERVAL '8 hours' ELSE INTERVAL '0 hours' END), INTERVAL '0 hours')
  INTO present_days, half_days, absent_days, late_count, total_hours, overtime_hours
  FROM attendance_records
  WHERE employee_id = emp_id
    AND attendance_date BETWEEN period_start AND period_end;
  
  result := json_build_object(
    'employee_id', emp_id,
    'period_start', period_start,
    'period_end', period_end,
    'present_days', present_days,
    'half_days', half_days,
    'absent_days', absent_days,
    'late_count', late_count,
    'total_hours', EXTRACT(EPOCH FROM total_hours) / 3600,
    'overtime_hours', EXTRACT(EPOCH FROM overtime_hours) / 3600
  );
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."rpc_get_attendance_summary"("emp_id" "uuid", "period_start" "date", "period_end" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_booking_branch_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.branch_id IS NULL AND NEW.created_by IS NOT NULL THEN
    SELECT branch_id INTO NEW.branch_id
    FROM public.user_profiles
    WHERE user_id = NEW.created_by
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_booking_branch_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_cancellation_invoice_id"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.cancellation_invoice_id IS NULL THEN
    NEW.cancellation_invoice_id := generate_cancellation_invoice_id();
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_cancellation_invoice_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_expense_branch_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.branch_id IS NULL AND NEW.created_by IS NOT NULL THEN
    SELECT branch_id INTO NEW.branch_id
    FROM public.user_profiles
    WHERE user_id = NEW.created_by
    LIMIT 1;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."set_expense_branch_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_user_roles"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only sync if user exists in auth.users
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.user_id) THEN
    -- Insert or update user role
    INSERT INTO public.user_roles (user_id, role)
    VALUES (NEW.user_id, NEW.role::app_role)
    ON CONFLICT (user_id, role) 
    DO UPDATE SET role = EXCLUDED.role, updated_at = now();
    
    RAISE NOTICE '✓ Successfully synced role % for user %', NEW.role, NEW.user_id;
  ELSE
    RAISE NOTICE 'ℹ️ User % does not exist in auth.users yet, skipping trigger sync', NEW.user_id;
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING '⚠️ Error syncing role for user %: %', NEW.user_id, SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_user_roles"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_agent_stats"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  agent_user_id UUID;
  agent_record_id UUID;
BEGIN
  -- Get agent user_id from referred_by_id
  IF NEW.referred_by_id IS NOT NULL THEN
    agent_user_id := NEW.referred_by_id;
    
    -- Get agent profile
    SELECT id INTO agent_record_id 
    FROM public.agent_profiles 
    WHERE user_id = agent_user_id;
    
    IF agent_record_id IS NOT NULL THEN
      -- Only update stats if booking is confirmed
      IF NEW.booking_status = 'Confirmed' AND (OLD.booking_status IS NULL OR OLD.booking_status != 'Confirmed') THEN
        UPDATE public.agent_profiles
        SET 
          total_leads_converted = total_leads_converted + 1,
          total_sales_value = total_sales_value + COALESCE(NEW.final_price_with_gst, 0),
          total_commission_earned = total_commission_earned + (COALESCE(NEW.final_price_with_gst, 0) * commission_rate / 100),
          updated_at = NOW()
        WHERE id = agent_record_id;
        
        -- Create commission record
        INSERT INTO public.commission_records (
          staff_id, booking_id, commission_type, booking_amount,
          commission_rate, commission_amount, created_by
        )
        VALUES (
          agent_record_id,
          NEW.id,
          'agent',
          NEW.final_price_with_gst,
          5.0,
          (NEW.final_price_with_gst * 5.0 / 100),
          NEW.created_by
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_agent_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_assigned_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- For INSERT: set assigned_at if assigned_to is provided
  IF TG_OP = 'INSERT' AND NEW.assigned_to IS NOT NULL THEN
    NEW.assigned_at := NOW();
  END IF;
  
  -- For UPDATE: set assigned_at if assigned_to changed and is not null
  IF TG_OP = 'UPDATE' THEN
    IF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to AND NEW.assigned_to IS NOT NULL THEN
      NEW.assigned_at := NOW();
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_assigned_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_attendance_submission_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_attendance_submission_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_commission_on_tour_completion"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Check if booking is confirmed and tour has ended
  IF NEW.booking_status = 'Confirmed' AND NEW.travel_end_date <= CURRENT_DATE THEN
    -- Update commission status to confirmed
    UPDATE commission_records
    SET 
      status = 'confirmed',
      updated_at = NOW()
    WHERE booking_id = NEW.id 
      AND commission_type = 'agent'
      AND status = 'pending';
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_commission_on_tour_completion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_invoice_approval_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_invoice_approval_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_overdue_tasks"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.tasks 
  SET status = 'Delayed', updated_at = now()
  WHERE deadline < now() 
    AND status NOT IN ('Completed', 'Delayed');
END;
$$;


ALTER FUNCTION "public"."update_overdue_tasks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_staff_monthly_target"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_staff_id uuid;
  v_target_month date;
  v_tour_cost numeric;
  v_pax_count integer;
  v_incentive_pct numeric;
  v_tour_target integer;
  v_pax_target integer;
BEGIN
  -- Handle booking completion
  IF NEW.booking_status = 'Completed' AND (OLD.booking_status IS NULL OR OLD.booking_status != 'Completed') THEN
    
    -- Get staff profile from created_by user
    SELECT sp.id, sp.monthly_tour_target, sp.monthly_pax_target, sp.incentive_percentage
    INTO v_staff_id, v_tour_target, v_pax_target, v_incentive_pct
    FROM staff_profiles sp
    WHERE sp.user_id = NEW.created_by
    AND sp.incentive_enabled = true;
    
    -- If staff profile found with incentive enabled
    IF v_staff_id IS NOT NULL THEN
      v_target_month := date_trunc('month', NEW.updated_at)::date;
      v_tour_cost := COALESCE(NEW.final_price_with_gst, 0);
      v_pax_count := COALESCE(NEW.number_of_adults, 0) + COALESCE(NEW.number_of_children, 0) + COALESCE(NEW.number_of_infants, 0);
      
      -- Insert or update monthly target record
      INSERT INTO staff_monthly_targets (
        staff_id,
        target_month,
        tour_target,
        pax_target,
        incentive_percentage,
        tours_completed,
        pax_completed,
        total_tour_value
      ) VALUES (
        v_staff_id,
        v_target_month,
        v_tour_target,
        v_pax_target,
        COALESCE(v_incentive_pct, 5.0),
        1,
        v_pax_count,
        v_tour_cost
      )
      ON CONFLICT (staff_id, target_month) DO UPDATE SET
        tours_completed = staff_monthly_targets.tours_completed + 1,
        pax_completed = staff_monthly_targets.pax_completed + v_pax_count,
        total_tour_value = staff_monthly_targets.total_tour_value + v_tour_cost,
        updated_at = now();
      
      -- Update target achievement status
      UPDATE staff_monthly_targets SET
        tour_target_met = (tour_target IS NULL OR tours_completed >= tour_target),
        pax_target_met = (pax_target IS NULL OR pax_completed >= pax_target),
        targets_achieved = (
          (tour_target IS NULL OR tours_completed >= tour_target) OR
          (pax_target IS NULL OR pax_completed >= pax_target)
        ),
        incentive_earned = CASE 
          WHEN (tour_target IS NULL OR tours_completed >= tour_target) OR
               (pax_target IS NULL OR pax_completed >= pax_target)
          THEN (total_tour_value * incentive_percentage / 100)
          ELSE 0
        END
      WHERE staff_id = v_staff_id 
        AND target_month = v_target_month;
    END IF;
  END IF;
  
  -- Handle cancellation (subtract from progress)
  IF OLD.booking_status = 'Completed' AND NEW.booking_status = 'Cancelled' THEN
    SELECT sp.id INTO v_staff_id
    FROM staff_profiles sp
    WHERE sp.user_id = NEW.created_by
    AND sp.incentive_enabled = true;
    
    IF v_staff_id IS NOT NULL THEN
      v_target_month := date_trunc('month', OLD.updated_at)::date;
      v_tour_cost := COALESCE(OLD.final_price_with_gst, 0);
      v_pax_count := COALESCE(OLD.number_of_adults, 0) + COALESCE(OLD.number_of_children, 0) + COALESCE(OLD.number_of_infants, 0);
      
      UPDATE staff_monthly_targets SET
        tours_completed = GREATEST(0, tours_completed - 1),
        pax_completed = GREATEST(0, pax_completed - v_pax_count),
        total_tour_value = GREATEST(0, total_tour_value - v_tour_cost),
        updated_at = now()
      WHERE staff_id = v_staff_id 
        AND target_month = v_target_month;
      
      -- Recalculate target achievement
      UPDATE staff_monthly_targets SET
        tour_target_met = (tour_target IS NULL OR tours_completed >= tour_target),
        pax_target_met = (pax_target IS NULL OR pax_completed >= pax_target),
        targets_achieved = (
          (tour_target IS NULL OR tours_completed >= tour_target) OR
          (pax_target IS NULL OR pax_completed >= pax_target)
        ),
        incentive_earned = CASE 
          WHEN targets_achieved THEN (total_tour_value * incentive_percentage / 100)
          ELSE 0
        END
      WHERE staff_id = v_staff_id 
        AND target_month = v_target_month;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_staff_monthly_target"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_staff_monthly_targets_on_booking"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  staff_profile_id UUID;
  target_record RECORD;
  total_pax INTEGER;
  booking_month DATE;
BEGIN
  -- Only proceed for confirmed bookings with assigned_to (staff)
  IF NEW.booking_status = 'Confirmed' AND NEW.assigned_to IS NOT NULL THEN
    -- Get staff profile from user_id
    SELECT id INTO staff_profile_id
    FROM staff_profiles
    WHERE user_id = NEW.assigned_to AND is_active = true;
    
    IF staff_profile_id IS NOT NULL THEN
      -- Calculate total PAX
      total_pax := NEW.number_of_adults + NEW.number_of_children + NEW.number_of_infants;
      
      -- Get month from travel start date
      booking_month := DATE_TRUNC('month', NEW.travel_start_date)::DATE;
      
      -- Get or create target for this month
      SELECT * INTO target_record
      FROM staff_monthly_targets
      WHERE staff_id = staff_profile_id
        AND target_month = booking_month;
      
      IF target_record IS NOT NULL THEN
        -- Update target progress
        UPDATE staff_monthly_targets
        SET 
          tours_completed = tours_completed + 1,
          pax_completed = pax_completed + total_pax,
          total_tour_value = total_tour_value + NEW.final_price_with_gst,
          tour_target_met = (tour_target IS NULL OR (tours_completed + 1) >= tour_target),
          pax_target_met = (pax_target IS NULL OR (pax_completed + total_pax) >= pax_target),
          targets_achieved = (
            (tour_target IS NULL OR (tours_completed + 1) >= tour_target) AND
            (pax_target IS NULL OR (pax_completed + total_pax) >= pax_target)
          ),
          incentive_earned = CASE
            WHEN (
              (tour_target IS NULL OR (tours_completed + 1) >= tour_target) AND
              (pax_target IS NULL OR (pax_completed + total_pax) >= pax_target)
            ) THEN (total_tour_value + NEW.final_price_with_gst) * (incentive_percentage / 100)
            ELSE 0
          END
        WHERE id = target_record.id;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_staff_monthly_targets_on_booking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."user_has_branch_access"("_user_id" "uuid", "_branch_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  user_role TEXT;
  user_branch_id UUID;
BEGIN
  IF _branch_id IS NULL THEN
    RETURN TRUE;
  END IF;
  
  SELECT role, branch_id INTO user_role, user_branch_id
  FROM public.user_profiles
  WHERE user_id = _user_id;
  
  IF user_role = 'admin' THEN
    RETURN TRUE;
  END IF;
  
  IF user_branch_id = _branch_id THEN
    RETURN TRUE;
  END IF;
  
  RETURN FALSE;
END;
$$;


ALTER FUNCTION "public"."user_has_branch_access"("_user_id" "uuid", "_branch_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_user_consistency"("user_email" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  result jsonb;
  auth_exists boolean;
  profile_exists boolean;
  role_exists boolean;
  user_id_from_profile uuid;
BEGIN
  -- Check auth.users
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE email = user_email) INTO auth_exists;
  
  -- Check user_profiles
  SELECT EXISTS(SELECT 1 FROM user_profiles WHERE email = user_email) INTO profile_exists;
  SELECT id INTO user_id_from_profile FROM user_profiles WHERE email = user_email LIMIT 1;
  
  -- Check user_roles (if profile exists)
  IF user_id_from_profile IS NOT NULL THEN
    SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id = user_id_from_profile) INTO role_exists;
  ELSE
    role_exists := false;
  END IF;
  
  result := jsonb_build_object(
    'email', user_email,
    'auth_exists', auth_exists,
    'profile_exists', profile_exists,
    'role_exists', role_exists,
    'consistent', (auth_exists AND profile_exists AND role_exists) OR (NOT auth_exists AND NOT profile_exists AND NOT role_exists),
    'user_id', user_id_from_profile
  );
  
  RETURN result;
END;
$$;


ALTER FUNCTION "public"."validate_user_consistency"("user_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."validate_user_profile_auth"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only validate if NOT being called by service role
  IF current_setting('request.jwt.claims', true)::json->>'role' != 'service_role' THEN
    -- Check if auth user exists (use user_id if available, otherwise id for backwards compatibility)
    IF NEW.user_id IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.user_id) THEN
        RAISE EXCEPTION 'Cannot create profile: auth user does not exist for user_id %', NEW.user_id;
      END IF;
    ELSIF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = NEW.id) THEN
      RAISE EXCEPTION 'Cannot create profile: auth user does not exist for ID %', NEW.id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."validate_user_profile_auth"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."validate_user_profile_auth"() IS 'Validates that a user_profile has a corresponding auth.users entry before creation';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."access_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "resource_type" "text" NOT NULL,
    "resource_id" "uuid",
    "access_granted" boolean NOT NULL,
    "reason" "text",
    "ip_address" "text",
    "user_agent" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."access_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."agent_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text" NOT NULL,
    "phone" "text",
    "commission_rate" numeric DEFAULT 5.0,
    "total_leads_assigned" integer DEFAULT 0,
    "total_leads_converted" integer DEFAULT 0,
    "total_sales_value" numeric DEFAULT 0,
    "total_commission_earned" numeric DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "pending_commission" numeric DEFAULT 0,
    "confirmed_commission" numeric DEFAULT 0
);


ALTER TABLE "public"."agent_profiles" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."agent_leaderboard" AS
 SELECT "id",
    "user_id",
    "name",
    "total_leads_assigned",
    "total_leads_converted",
    "total_sales_value",
    "total_commission_earned",
        CASE
            WHEN ("total_leads_assigned" > 0) THEN "round"(((("total_leads_converted")::numeric / ("total_leads_assigned")::numeric) * (100)::numeric), 2)
            ELSE (0)::numeric
        END AS "conversion_rate",
    "rank"() OVER (ORDER BY "total_commission_earned" DESC) AS "rank"
   FROM "public"."agent_profiles" "ap"
  WHERE ("is_active" = true)
  ORDER BY "total_commission_earned" DESC;


ALTER VIEW "public"."agent_leaderboard" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."api_access_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "endpoint" "text" NOT NULL,
    "method" "text" NOT NULL,
    "status_code" integer,
    "request_body" "jsonb",
    "response_body" "jsonb",
    "ip_address" "text",
    "user_agent" "text",
    "device_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."api_access_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_notification_recipients" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "notification_id" "uuid",
    "user_id" "uuid",
    "delivered_at" timestamp with time zone,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('Asia/Kolkata'::"text", "now"())
);


ALTER TABLE "public"."app_notification_recipients" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_notification_recipients_backup" (
    "id" "uuid",
    "notification_id" "uuid",
    "user_id" "uuid",
    "delivered_at" timestamp with time zone,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone
);


ALTER TABLE "public"."app_notification_recipients_backup" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "branch_id" "uuid",
    "send_to_all" boolean DEFAULT false,
    "scheduled_for" timestamp with time zone,
    "status" "text" DEFAULT 'draft'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('Asia/Kolkata'::"text", "now"()),
    "sent_at" timestamp with time zone,
    "updated_at" timestamp with time zone DEFAULT "timezone"('Asia/Kolkata'::"text", "now"()),
    CONSTRAINT "app_notifications_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'scheduled'::"text", 'sent'::"text", 'failed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."app_notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "attendance_date" "date" NOT NULL,
    "checkin_at" timestamp with time zone,
    "checkin_lat" numeric,
    "checkin_lng" numeric,
    "checkin_source" "text" DEFAULT 'manual'::"text",
    "checkout_at" timestamp with time zone,
    "checkout_lat" numeric,
    "checkout_lng" numeric,
    "checkout_source" "text",
    "total_hours" interval,
    "status" "text" DEFAULT 'present'::"text",
    "late_flag" boolean DEFAULT false,
    "early_exit_flag" boolean DEFAULT false,
    "notes" "text",
    "geofence_id" "uuid",
    "photo_url" "text",
    "accuracy_meters" numeric,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "branch_id" "uuid",
    "face_verified" boolean DEFAULT false,
    "uniform_verified" boolean DEFAULT false,
    "id_card_verified" boolean DEFAULT false,
    "selfie_path" "text",
    "approval_time" timestamp with time zone,
    "rejection_reasons" "text"[],
    "approved_by" "uuid",
    "late_by_minutes" integer DEFAULT 0,
    "is_out_of_geofence" boolean DEFAULT false,
    "submitted_attempt_number" integer DEFAULT 1,
    "mark_for_payroll_deduction" boolean DEFAULT false,
    CONSTRAINT "attendance_records_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."attendance_records" OWNER TO "postgres";


COMMENT ON COLUMN "public"."attendance_records"."status" IS 'Approval status: pending | approved | rejected';



COMMENT ON COLUMN "public"."attendance_records"."selfie_path" IS 'Storage path in attendance-selfies bucket';



COMMENT ON COLUMN "public"."attendance_records"."approval_time" IS 'Timestamp when attendance was approved/rejected';



COMMENT ON COLUMN "public"."attendance_records"."rejection_reasons" IS 'Array of rejection reasons from admin/manager';



COMMENT ON COLUMN "public"."attendance_records"."approved_by" IS 'User ID of admin/manager who approved/rejected';



COMMENT ON COLUMN "public"."attendance_records"."late_by_minutes" IS 'Minutes late compared to schedule';



COMMENT ON COLUMN "public"."attendance_records"."is_out_of_geofence" IS 'Whether submission was outside geofence';



COMMENT ON COLUMN "public"."attendance_records"."submitted_attempt_number" IS 'Attempt number for this date (max 3)';



COMMENT ON COLUMN "public"."attendance_records"."mark_for_payroll_deduction" IS 'Flag to mark attendance rejection for payroll deduction';



CREATE TABLE IF NOT EXISTS "public"."attendance_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "branch_id" "uuid",
    "checkin_time" time without time zone NOT NULL,
    "checkout_time" time without time zone NOT NULL,
    "shift_name" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."attendance_shifts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."attendance_submissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "attendance_record_id" "uuid",
    "employee_id" "uuid" NOT NULL,
    "submitted_at" timestamp with time zone DEFAULT "now"(),
    "selfie_path" "text" NOT NULL,
    "status" "text" NOT NULL,
    "rejection_reasons" "text"[],
    "admin_id" "uuid",
    "admin_notes" "text",
    "attempt_number" integer NOT NULL,
    "checkin_lat" double precision,
    "checkin_lng" double precision,
    "is_out_of_geofence" boolean DEFAULT false,
    "late_by_minutes" integer DEFAULT 0,
    "branch_id" "uuid",
    "geofence_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "attendance_submissions_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."attendance_submissions" OWNER TO "postgres";


COMMENT ON TABLE "public"."attendance_submissions" IS 'Audit log of all attendance submission attempts';



CREATE TABLE IF NOT EXISTS "public"."booking_approval_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requester_name" "text" NOT NULL,
    "requester_role" "text" NOT NULL,
    "booking_details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reviewed_by" "uuid",
    "reviewer_name" "text",
    "reviewer_role" "text",
    "reviewed_at" timestamp with time zone,
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "booking_approval_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);

ALTER TABLE ONLY "public"."booking_approval_requests" REPLICA IDENTITY FULL;


ALTER TABLE "public"."booking_approval_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_id_sequences" (
    "year" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."booking_id_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."booking_vendor_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "vendor_id" "uuid" NOT NULL,
    "service_type" "text" NOT NULL,
    "rate_list_id" "uuid",
    "room_category" "text",
    "season_id" "uuid",
    "meal_plan" "text",
    "car_type" "text",
    "quantity" numeric DEFAULT 1 NOT NULL,
    "unit_price" numeric DEFAULT 0 NOT NULL,
    "total_price" numeric DEFAULT 0 NOT NULL,
    "start_date" "date",
    "end_date" "date",
    "payment_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "booking_vendor_items_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['pending'::"text", 'part_paid'::"text", 'fully_paid'::"text"]))),
    CONSTRAINT "booking_vendor_items_service_type_check" CHECK (("service_type" = ANY (ARRAY['hotel'::"text", 'car'::"text"])))
);


ALTER TABLE "public"."booking_vendor_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "text" NOT NULL,
    "customer_name" "text" NOT NULL,
    "customer_email" "text",
    "customer_phone" "text",
    "customer_address" "text",
    "tour_category" "text" NOT NULL,
    "tour_package_id" "uuid",
    "tour_package_name" "text" NOT NULL,
    "travel_start_date" "date" NOT NULL,
    "travel_end_date" "date" NOT NULL,
    "number_of_adults" integer DEFAULT 1 NOT NULL,
    "number_of_children" integer DEFAULT 0,
    "number_of_infants" integer DEFAULT 0,
    "children_percentage" numeric DEFAULT 50,
    "infants_percentage" numeric DEFAULT 25,
    "adult_price" numeric NOT NULL,
    "child_price" numeric DEFAULT 0,
    "infant_price" numeric DEFAULT 0,
    "final_selling_price" numeric NOT NULL,
    "gst_enabled" boolean DEFAULT false,
    "gst_amount" numeric DEFAULT 0,
    "final_price_with_gst" numeric NOT NULL,
    "advance_received" numeric DEFAULT 0,
    "balance_amount" numeric DEFAULT 0,
    "payment_method" "text",
    "payment_status" "text" DEFAULT 'Pending'::"text",
    "booking_status" "text" DEFAULT 'Processing'::"text",
    "source_type" "text" DEFAULT 'Direct'::"text",
    "referred_by_id" "uuid",
    "commission_percentage" numeric DEFAULT 0,
    "commission_amount" numeric DEFAULT 0,
    "lead_id" "uuid",
    "quotation_id" "uuid",
    "hotel_vendor_id" "uuid",
    "hotel_rate_list_id" "uuid",
    "car_vendor_id" "uuid",
    "car_rate_list_id" "uuid",
    "vendor_cost_breakdown" "jsonb" DEFAULT '{}'::"jsonb",
    "traveller_details" "jsonb" DEFAULT '[]'::"jsonb",
    "traveller_details_filled" boolean DEFAULT false,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "addon_items" "jsonb" DEFAULT '[]'::"jsonb",
    "discount_type" "text",
    "discount_percentage" numeric DEFAULT 0,
    "discount_amount" numeric DEFAULT 0,
    "gst_type" "text",
    "approval_status" "text" DEFAULT 'approved'::"text",
    "approval_notes" "text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "rejected_reason" "text",
    "group_tour_date_id" "uuid",
    "branch_id" "uuid",
    "assigned_to" "uuid",
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone,
    "dmc_vendor_id" "uuid",
    "dmc_cost_per_head" numeric DEFAULT 0,
    "dmc_total_cost" numeric DEFAULT 0,
    CONSTRAINT "bookings_approval_status_check" CHECK (("approval_status" = ANY (ARRAY['pending_approval'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "bookings_gst_type_check" CHECK ((("gst_type" = ANY (ARRAY['IGST'::"text", 'CGST_SGST'::"text"])) OR ("gst_type" IS NULL)))
);

ALTER TABLE ONLY "public"."bookings" REPLICA IDENTITY FULL;


ALTER TABLE "public"."bookings" OWNER TO "postgres";


COMMENT ON COLUMN "public"."bookings"."assigned_to" IS 'Staff member assigned to handle this booking';



COMMENT ON COLUMN "public"."bookings"."assigned_by" IS 'User who assigned this booking';



COMMENT ON COLUMN "public"."bookings"."assigned_at" IS 'Timestamp when booking was assigned';



CREATE TABLE IF NOT EXISTS "public"."branch_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "branch_id" "uuid",
    "action" "text" NOT NULL,
    "performed_by" "uuid",
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    "affected_records" "jsonb" DEFAULT '{}'::"jsonb",
    "timestamp" timestamp with time zone DEFAULT "now"(),
    "ip_address" "text",
    "user_agent" "text"
);


ALTER TABLE "public"."branch_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."branches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "location" "text" NOT NULL,
    "name" "text" GENERATED ALWAYS AS (('Spectrum - '::"text" || "location")) STORED NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "active" boolean DEFAULT true NOT NULL,
    "code" "text",
    "latitude" numeric(10,8),
    "longitude" numeric(11,8)
);


ALTER TABLE "public"."branches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."office_geofences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "center_lat" numeric NOT NULL,
    "center_lng" numeric NOT NULL,
    "radius_meters" integer DEFAULT 100 NOT NULL,
    "branch_id" "uuid",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."office_geofences" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."branch_geofence_view" AS
 SELECT "b"."id" AS "branch_id",
    "b"."name" AS "branch_name",
    "b"."location",
    "b"."latitude",
    "b"."longitude",
    "g"."id" AS "geofence_id",
    "g"."center_lat" AS "geofence_lat",
    "g"."center_lng" AS "geofence_lng",
    "g"."radius_meters",
    "g"."active" AS "geofence_active"
   FROM ("public"."branches" "b"
     LEFT JOIN "public"."office_geofences" "g" ON (("g"."branch_id" = "b"."id")));


ALTER VIEW "public"."branch_geofence_view" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cancellation_invoice_sequences" (
    "id" integer NOT NULL,
    "year" integer DEFAULT EXTRACT(year FROM CURRENT_DATE) NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cancellation_invoice_sequences" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."cancellation_invoice_sequences_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."cancellation_invoice_sequences_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."cancellation_invoice_sequences_id_seq" OWNED BY "public"."cancellation_invoice_sequences"."id";



CREATE TABLE IF NOT EXISTS "public"."car_rate_lists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vendor_id" "uuid" NOT NULL,
    "title" "text" DEFAULT 'Default Car Rate List'::"text" NOT NULL,
    "location" "text" NOT NULL,
    "currency" "text" DEFAULT 'INR'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."car_rate_lists" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."car_rate_rows" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "car_type" "text" NOT NULL,
    "price_per_day" numeric,
    "price_per_km" numeric,
    "driver_allowance" numeric,
    "fuel_charges" numeric,
    "toll_charges" numeric,
    "parking_charges" numeric,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."car_rate_rows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."car_rate_seasons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rate_list_id" "uuid" NOT NULL,
    "season_name" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."car_rate_seasons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commission_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "payroll_record_id" "uuid",
    "commission_type" "text" NOT NULL,
    "booking_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "commission_rate" numeric(5,2) DEFAULT 0 NOT NULL,
    "commission_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "earned_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "payout_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text",
    CONSTRAINT "commission_records_commission_type_check" CHECK (("commission_type" = ANY (ARRAY['agent'::"text", 'staff'::"text", 'manager'::"text"]))),
    CONSTRAINT "commission_records_payout_status_check" CHECK (("payout_status" = ANY (ARRAY['pending'::"text", 'processed'::"text", 'paid'::"text"])))
);


ALTER TABLE "public"."commission_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."company_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "logo_url" "text",
    "company_name" "text" DEFAULT 'Your Company'::"text",
    "primary_color" "text" DEFAULT '#3b82f6'::"text",
    "secondary_color" "text" DEFAULT '#64748b'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_by" "uuid",
    "birthday_message_template" "text" DEFAULT '🎉 Happy Birthday {name}! Wishing you a wonderful year ahead filled with happiness and success. – {company_name}'::"text"
);


ALTER TABLE "public"."company_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."deletion_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "requester_id" "uuid" NOT NULL,
    "requester_role" "text" NOT NULL,
    "module_name" "text" NOT NULL,
    "record_id" "uuid" NOT NULL,
    "record_details" "jsonb" DEFAULT '{}'::"jsonb",
    "reason" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    CONSTRAINT "deletion_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "valid_status" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."deletion_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."deletion_requests" IS 'Stores deletion requests from managers that require admin approval';



CREATE TABLE IF NOT EXISTS "public"."device_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_id" "text" NOT NULL,
    "device_type" "text",
    "app_version" "text",
    "last_active" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."device_sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dmc_vendor_packages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "dmc_vendor_id" "uuid" NOT NULL,
    "tour_package_id" "uuid" NOT NULL,
    "admin_selling_price" numeric DEFAULT 0 NOT NULL,
    "vendor_cost_per_head" numeric DEFAULT 0 NOT NULL,
    "estimated_profit_per_head" numeric GENERATED ALWAYS AS (("admin_selling_price" - "vendor_cost_per_head")) STORED,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid"
);


ALTER TABLE "public"."dmc_vendor_packages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."employee_code_sequences" (
    "year" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."employee_code_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expense_bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "expense_id" "uuid" NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."expense_bookings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."expenses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "expense_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "branch" "text" DEFAULT 'Main Branch'::"text" NOT NULL,
    "category" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "payment_mode" "text" NOT NULL,
    "booking_id" "uuid",
    "vendor_id" "uuid",
    "paid_to" "text",
    "notes" "text",
    "receipt_url" "text",
    "status" "text" DEFAULT 'submitted'::"text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "group_id" "uuid",
    "expense_type" "text" DEFAULT 'general'::"text" NOT NULL,
    "branch_id" "uuid",
    CONSTRAINT "expenses_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "expenses_category_check" CHECK (("category" = ANY (ARRAY['Staff Tickets'::"text", 'Kitchen/Dining'::"text", 'Manager Salary'::"text", 'Cooking Staff Salary'::"text", 'Grocery Cost'::"text", 'Tips'::"text", 'Office Rent'::"text", 'Utilities'::"text", 'Stationery'::"text", 'Marketing'::"text", 'Vehicle Maintenance'::"text", 'Customer Hospitality'::"text", 'Miscellaneous'::"text", 'Chef Salary'::"text", 'Food & Groceries'::"text", 'Transportation'::"text", 'Accommodation'::"text", 'Guide Fees'::"text", 'Emergency Expenses'::"text"]))),
    CONSTRAINT "expenses_expense_type_check" CHECK (("expense_type" = ANY (ARRAY['general'::"text", 'tour_extra'::"text"]))),
    CONSTRAINT "expenses_payment_mode_check" CHECK (("payment_mode" = ANY (ARRAY['Cash'::"text", 'Bank Transfer'::"text", 'UPI'::"text", 'Card'::"text", 'Cheque'::"text", 'Online'::"text", 'Petty Cash'::"text"]))),
    CONSTRAINT "expenses_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'submitted'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."expenses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_tour_capacity_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_tour_date_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "previous_capacity" integer NOT NULL,
    "new_capacity" integer NOT NULL,
    "pax_count" integer NOT NULL,
    "changed_by" "uuid",
    "changed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reason" "text"
);


ALTER TABLE "public"."group_tour_capacity_audit" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."group_tour_dates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "package_id" "uuid" NOT NULL,
    "travel_date" "date" NOT NULL,
    "capacity_total" integer DEFAULT 0 NOT NULL,
    "capacity_remaining" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "capacity_check" CHECK (("capacity_remaining" >= 0)),
    CONSTRAINT "capacity_remaining_lte_total" CHECK (("capacity_remaining" <= "capacity_total")),
    CONSTRAINT "capacity_total_check" CHECK (("capacity_total" >= 0))
);


ALTER TABLE "public"."group_tour_dates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hotel_rate_lists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vendor_id" "uuid" NOT NULL,
    "title" "text" DEFAULT 'Default Rate List'::"text" NOT NULL,
    "location" "text" NOT NULL,
    "currency" "text" DEFAULT 'INR'::"text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL
);

ALTER TABLE ONLY "public"."hotel_rate_lists" REPLICA IDENTITY FULL;


ALTER TABLE "public"."hotel_rate_lists" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hotel_rate_rows" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "season_id" "uuid" NOT NULL,
    "room_category" "text" NOT NULL,
    "meal_plan" "text",
    "price_cp" numeric,
    "price_map" numeric,
    "extra_bed" numeric,
    "cnb_5_12" numeric,
    "children_below_5" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "price_ep" numeric,
    "price_ap" numeric,
    CONSTRAINT "check_at_least_one_price" CHECK ((("price_cp" IS NOT NULL) OR ("price_map" IS NOT NULL)))
);

ALTER TABLE ONLY "public"."hotel_rate_rows" REPLICA IDENTITY FULL;


ALTER TABLE "public"."hotel_rate_rows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."hotel_rate_seasons" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rate_list_id" "uuid" NOT NULL,
    "season_name" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "check_season_dates" CHECK (("start_date" <= "end_date"))
);

ALTER TABLE ONLY "public"."hotel_rate_seasons" REPLICA IDENTITY FULL;


ALTER TABLE "public"."hotel_rate_seasons" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."incentive_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "payroll_record_id" "uuid",
    "incentive_type" "text" NOT NULL,
    "booking_id" "uuid",
    "amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "criteria_met" "jsonb" DEFAULT '{}'::"jsonb",
    "earned_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "payout_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    CONSTRAINT "incentive_records_payout_status_check" CHECK (("payout_status" = ANY (ARRAY['pending'::"text", 'processed'::"text", 'paid'::"text"])))
);


ALTER TABLE "public"."incentive_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoice_approval_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "requested_by" "uuid" NOT NULL,
    "requester_name" "text" NOT NULL,
    "requester_role" "text" NOT NULL,
    "invoice_details" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reviewed_by" "uuid",
    "reviewer_name" "text",
    "reviewer_role" "text",
    "reviewed_at" timestamp with time zone,
    "rejection_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "invoice_approval_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."invoice_approval_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoice_cancellations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "original_invoice_id" "uuid" NOT NULL,
    "cancellation_invoice_id" "text",
    "client_name" "text" NOT NULL,
    "client_contact" "text" NOT NULL,
    "client_email" "text",
    "cancellation_charge_type" "text" NOT NULL,
    "cancellation_charge_value" numeric NOT NULL,
    "cancellation_charge_amount" numeric NOT NULL,
    "package_name" "text" NOT NULL,
    "booking_id" "text",
    "tour_start_date" "date",
    "tour_end_date" "date",
    "cancellation_remarks" "text",
    "default_remarks" "text" DEFAULT 'As per your request, this tour booking has been cancelled. As per our policy, the cancellation charges to pay are as follows. This amount needs to be paid at the earliest to avoid any serious actions. We hope you travel with us in the future.'::"text",
    "payment_status" "text" DEFAULT 'Pending'::"text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "invoice_cancellations_cancellation_charge_type_check" CHECK (("cancellation_charge_type" = ANY (ARRAY['percentage'::"text", 'fixed'::"text"]))),
    CONSTRAINT "invoice_cancellations_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['Pending'::"text", 'Paid'::"text"])))
);


ALTER TABLE "public"."invoice_cancellations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoice_non_gst_sequences" (
    "id" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."invoice_non_gst_sequences" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."invoice_non_gst_sequences_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."invoice_non_gst_sequences_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."invoice_non_gst_sequences_id_seq" OWNED BY "public"."invoice_non_gst_sequences"."id";



CREATE TABLE IF NOT EXISTS "public"."invoice_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "booking_id" "uuid",
    "payee_type" "text" NOT NULL,
    "payee_id" "uuid",
    "payee_name" "text",
    "amount" numeric NOT NULL,
    "method" "text" DEFAULT 'Cash'::"text",
    "paid_on" "date" DEFAULT CURRENT_DATE NOT NULL,
    "note" "text",
    "receipt_url" "text",
    "recorded_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "receipt_number" "text",
    CONSTRAINT "invoice_payments_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "invoice_payments_method_check" CHECK (("method" = ANY (ARRAY['Cash'::"text", 'Bank'::"text", 'UPI'::"text", 'Card'::"text", 'Other'::"text"]))),
    CONSTRAINT "invoice_payments_payee_type_check" CHECK (("payee_type" = ANY (ARRAY['spectrum'::"text", 'hotel_vendor'::"text", 'car_vendor'::"text", 'other'::"text"])))
);


ALTER TABLE "public"."invoice_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoice_sequences" (
    "id" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."invoice_sequences" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."invoice_sequences_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."invoice_sequences_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."invoice_sequences_id_seq" OWNED BY "public"."invoice_sequences"."id";



CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_name" "text" NOT NULL,
    "client_contact" "text" NOT NULL,
    "client_email" "text",
    "booking_id" "uuid",
    "quotation_ref" "text",
    "package_name" "text" NOT NULL,
    "base_price" numeric NOT NULL,
    "gst_type" "text" NOT NULL,
    "gst_amount" numeric NOT NULL,
    "total_amount" numeric NOT NULL,
    "paid_amount" numeric DEFAULT 0,
    "pending_amount" numeric NOT NULL,
    "pdf_url" "text",
    "status" "text" DEFAULT 'Generated'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "customer_gstin" "text",
    "remarks" "text",
    "invoice_id" "text",
    "pan_no" "text",
    "hsn_sac_code" "text",
    "no_of_rooms" integer,
    "tour_duration_days" integer,
    "tour_duration_nights" integer,
    "tour_start_date" "date",
    "tour_end_date" "date",
    "number_of_adults" integer DEFAULT 0,
    "number_of_children" integer DEFAULT 0,
    "number_of_infants" integer DEFAULT 0,
    "addon_name" "text",
    "addon_price" numeric DEFAULT 0,
    "discount_type" "text",
    "discount_percentage" numeric DEFAULT 0,
    "discount_amount" numeric DEFAULT 0,
    "net_amount" numeric,
    "cgst_amount" numeric DEFAULT 0,
    "sgst_amount" numeric DEFAULT 0,
    "igst_amount" numeric DEFAULT 0,
    "booking_linked" boolean DEFAULT false,
    "approval_status" "text" DEFAULT 'approved'::"text",
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "branch_id" "uuid",
    "is_cancelled" boolean DEFAULT false,
    "cancelled_at" timestamp with time zone,
    "cancelled_by" "uuid",
    "cancellation_reason" "text",
    "client_address" "text",
    CONSTRAINT "invoices_approval_status_check" CHECK (("approval_status" = ANY (ARRAY['pending_approval'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "invoices_gst_type_check" CHECK (("gst_type" = ANY (ARRAY['IGST'::"text", 'CGST_SGST'::"text", 'NO_GST'::"text"]))),
    CONSTRAINT "invoices_status_check" CHECK (("status" = ANY (ARRAY['Generated'::"text", 'Sent'::"text", 'Paid'::"text", 'Cancelled'::"text"])))
);

ALTER TABLE ONLY "public"."invoices" REPLICA IDENTITY FULL;


ALTER TABLE "public"."invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."kpi_scores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "period_start" "date" NOT NULL,
    "period_end" "date" NOT NULL,
    "task_completion_pct" numeric DEFAULT 0,
    "on_time_completion_pct" numeric DEFAULT 0,
    "task_quality_score" numeric DEFAULT 0,
    "task_communication_score" numeric DEFAULT 0,
    "attendance_pct" numeric DEFAULT 0,
    "sales_value" numeric DEFAULT 0,
    "bookings_closed" integer DEFAULT 0,
    "final_score" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."kpi_scores" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lead_activities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "activity_type" "text" NOT NULL,
    "description" "text" NOT NULL,
    "scheduled_date" timestamp with time zone,
    "completed" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    CONSTRAINT "lead_activities_activity_type_check" CHECK (("activity_type" = ANY (ARRAY['Note'::"text", 'Call'::"text", 'Email'::"text", 'WhatsApp'::"text", 'Meeting'::"text", 'Follow-up'::"text"])))
);

ALTER TABLE ONLY "public"."lead_activities" REPLICA IDENTITY FULL;


ALTER TABLE "public"."lead_activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lead_details" (
    "lead_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "number_of_children_with_age" "text" NOT NULL,
    "expected_date_of_journey" "date",
    "expected_date_of_return" "date",
    "number_of_rooms_needed" numeric,
    "preferred_airline" "text",
    "preferred_accommodation_type" "text",
    "star_rating_preference" "text",
    "meal_plan" "text",
    "extra_meals" "text",
    "purpose_of_tour" "text",
    "ticketing_required" "text",
    "additional_notes" "text",
    "address" "text",
    "destination" "text",
    "number_of_adults" numeric,
    "budget" numeric
);


ALTER TABLE "public"."lead_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."lead_id_sequences" (
    "year" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."lead_id_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "destination" "text",
    "travel_dates_start" "date",
    "travel_dates_end" "date",
    "source" "text" DEFAULT 'Website'::"text",
    "status" "text" DEFAULT 'New'::"text",
    "assigned_to" "uuid",
    "budget" numeric(10,2),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "temperature_tag" "text",
    "follow_up_date" "date",
    "lead_id" "text",
    "source_type" "text" DEFAULT 'manual'::"text",
    "source_reference_id" "uuid",
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "branch_id" "uuid",
    "assigned_by" "uuid",
    "assigned_at" timestamp with time zone,
    "date_of_birth" "date",
    CONSTRAINT "leads_status_check" CHECK (("status" = ANY (ARRAY['New'::"text", 'In Process'::"text", 'Quotation Sent'::"text", 'Converted'::"text", 'Dropped'::"text"]))),
    CONSTRAINT "leads_temperature_tag_check" CHECK (("temperature_tag" = ANY (ARRAY['Hot'::"text", 'Warm'::"text", 'Cold'::"text"])))
);

ALTER TABLE ONLY "public"."leads" REPLICA IDENTITY FULL;


ALTER TABLE "public"."leads" OWNER TO "postgres";


COMMENT ON COLUMN "public"."leads"."assigned_by" IS 'User who assigned this lead to the staff member';



COMMENT ON COLUMN "public"."leads"."assigned_at" IS 'Timestamp when lead was assigned';



CREATE TABLE IF NOT EXISTS "public"."leave_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "employee_id" "uuid" NOT NULL,
    "leave_type" "text" NOT NULL,
    "from_date" "date" NOT NULL,
    "to_date" "date" NOT NULL,
    "days" numeric NOT NULL,
    "reason" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "manager_id" "uuid",
    "approved_at" timestamp with time zone,
    "manager_notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "leave_requests_leave_type_check" CHECK (("leave_type" = ANY (ARRAY['paid'::"text", 'unpaid'::"text", 'sick'::"text", 'casual'::"text"]))),
    CONSTRAINT "leave_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."leave_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."module_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role" "public"."app_role" NOT NULL,
    "module_name" "text" NOT NULL,
    "can_view" boolean DEFAULT false,
    "can_add" boolean DEFAULT false,
    "can_edit" boolean DEFAULT false,
    "can_delete" boolean DEFAULT false,
    "field_restrictions" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."module_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "title" "text" NOT NULL,
    "message" "text" NOT NULL,
    "data" "jsonb" DEFAULT '{}'::"jsonb",
    "read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    "reference_id" "uuid"
);

ALTER TABLE ONLY "public"."notifications" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."package_id_sequences" (
    "category" "text" NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL
);


ALTER TABLE "public"."package_id_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payroll_deductions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payroll_record_id" "uuid" NOT NULL,
    "epf" numeric DEFAULT 0,
    "esi" numeric DEFAULT 0,
    "professional_tax" numeric DEFAULT 0,
    "loan_recovery" numeric DEFAULT 0,
    "total_deductions" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."payroll_deductions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payroll_earnings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payroll_record_id" "uuid" NOT NULL,
    "basic_wage" numeric DEFAULT 0,
    "hra" numeric DEFAULT 0,
    "conveyance_allowance" numeric DEFAULT 0,
    "medical_allowance" numeric DEFAULT 0,
    "other_allowances" numeric DEFAULT 0,
    "total_earnings" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "incentive_amount" numeric DEFAULT 0
);


ALTER TABLE "public"."payroll_earnings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payroll_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "pay_period_start" "date" NOT NULL,
    "pay_period_end" "date" NOT NULL,
    "base_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "allowances_total" numeric(12,2) DEFAULT 0 NOT NULL,
    "deductions_total" numeric(12,2) DEFAULT 0 NOT NULL,
    "commission_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "incentives_amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "attendance_deduction" numeric(12,2) DEFAULT 0 NOT NULL,
    "manual_adjustments" numeric(12,2) DEFAULT 0 NOT NULL,
    "gross_salary" numeric(12,2) DEFAULT 0 NOT NULL,
    "net_salary" numeric(12,2) DEFAULT 0 NOT NULL,
    "working_days" integer DEFAULT 0 NOT NULL,
    "present_days" integer DEFAULT 0 NOT NULL,
    "leave_days" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "processed_at" timestamp with time zone,
    "processed_by" "uuid",
    "salary_slip_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "uan" "text",
    "pf_no" "text",
    "esi_no" "text",
    "bank_name" "text",
    "bank_account_no" "text",
    "paid_days" integer,
    "leaves_taken" integer DEFAULT 0,
    "lop_days" integer DEFAULT 0,
    CONSTRAINT "payroll_records_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'processed'::"text", 'paid'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."payroll_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "name" "text",
    "role" "text" DEFAULT 'staff'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "gender" "text",
    "branch_id" "uuid",
    "is_active" boolean DEFAULT true,
    "user_id" "uuid" NOT NULL,
    "manager_id" "uuid",
    "date_of_birth" "date",
    CONSTRAINT "user_profiles_gender_check" CHECK (("gender" = ANY (ARRAY['He'::"text", 'She'::"text"]))),
    CONSTRAINT "user_profiles_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'manager'::"text", 'staff'::"text", 'accounts'::"text", 'hrms'::"text", 'agent'::"text"])))
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


COMMENT ON TABLE "public"."user_profiles" IS 'User profile data. Authentication is handled by Supabase Auth (auth.users table). Roles are stored in user_roles table.';



COMMENT ON COLUMN "public"."user_profiles"."manager_id" IS 'References the manager who oversees this user (for staff assignments)';



CREATE OR REPLACE VIEW "public"."pending_attendance_with_details" AS
 SELECT "ar"."id",
    "ar"."employee_id",
    "ar"."attendance_date",
    "ar"."checkin_at",
    "ar"."checkin_lat",
    "ar"."checkin_lng",
    "ar"."status",
    "ar"."selfie_path",
    "ar"."submitted_attempt_number",
    "ar"."is_out_of_geofence",
    "ar"."late_by_minutes",
    "ar"."late_flag",
    "ar"."branch_id",
    "ar"."geofence_id",
    "ar"."rejection_reasons",
    "ar"."approval_time",
    "ar"."approved_by",
    "up"."name" AS "employee_name",
    "up"."email" AS "employee_email",
    "up"."role" AS "employee_role",
    "b"."name" AS "branch_name",
    "b"."location" AS "branch_location",
    "ar"."created_at" AS "submitted_at",
    (EXTRACT(epoch FROM ("now"() - "ar"."created_at")) / (3600)::numeric) AS "pending_hours"
   FROM (("public"."attendance_records" "ar"
     LEFT JOIN "public"."user_profiles" "up" ON (("ar"."employee_id" = "up"."user_id")))
     LEFT JOIN "public"."branches" "b" ON (("ar"."branch_id" = "b"."id")))
  WHERE ("ar"."status" = 'pending'::"text")
  ORDER BY "ar"."created_at";


ALTER VIEW "public"."pending_attendance_with_details" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."petty_cash_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transaction_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "payment_mode" "text" NOT NULL,
    "reference" "text",
    "notes" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "payer_name" "text",
    "receipt_number" "text",
    "purpose" "text",
    "received_from" "text",
    CONSTRAINT "petty_cash_ledger_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "petty_cash_ledger_payment_mode_check" CHECK (("payment_mode" = ANY (ARRAY['cash'::"text", 'bank'::"text", 'upi'::"text", 'card'::"text"]))),
    CONSTRAINT "petty_cash_ledger_type_check" CHECK (("type" = ANY (ARRAY['opening_balance'::"text", 'cash_in'::"text", 'cash_out'::"text"])))
);


ALTER TABLE "public"."petty_cash_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quotation_markup_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "group_markup_percentage" numeric DEFAULT 15.0 NOT NULL,
    "dmc_markup_percentage" numeric DEFAULT 10.0 NOT NULL,
    "customize_markup_percentage" numeric DEFAULT 20.0 NOT NULL,
    "readymade_markup_percentage" numeric DEFAULT 18.0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    CONSTRAINT "valid_markup_percentages" CHECK ((("group_markup_percentage" >= (0)::numeric) AND ("group_markup_percentage" <= (50)::numeric) AND ("dmc_markup_percentage" >= (0)::numeric) AND ("dmc_markup_percentage" <= (50)::numeric) AND ("customize_markup_percentage" >= (0)::numeric) AND ("customize_markup_percentage" <= (50)::numeric) AND ("readymade_markup_percentage" >= (0)::numeric) AND ("readymade_markup_percentage" <= (50)::numeric)))
);


ALTER TABLE "public"."quotation_markup_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quotations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_name" "text" NOT NULL,
    "number_of_adults" integer DEFAULT 1 NOT NULL,
    "number_of_children" integer DEFAULT 0 NOT NULL,
    "home_address" "text" NOT NULL,
    "phone_no" "text" NOT NULL,
    "email_address" "text",
    "travel_date" "date" NOT NULL,
    "tour_package_id" "uuid",
    "tour_package_category" "text" NOT NULL,
    "rooms_data" "jsonb" DEFAULT '[]'::"jsonb",
    "cars_data" "jsonb" DEFAULT '[]'::"jsonb",
    "addons_data" "jsonb" DEFAULT '[]'::"jsonb",
    "package_base_amount" numeric DEFAULT 0,
    "rooms_amount" numeric DEFAULT 0,
    "cars_amount" numeric DEFAULT 0,
    "addons_amount" numeric DEFAULT 0,
    "subtotal" numeric DEFAULT 0,
    "cgst" numeric DEFAULT 0,
    "sgst" numeric DEFAULT 0,
    "grand_total" numeric DEFAULT 0,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "additional_notes" "text",
    "food_cost_amount" numeric DEFAULT 0,
    "staff_ticket_amount" numeric DEFAULT 0,
    "base_cost" numeric DEFAULT 0,
    "markup_amount" numeric DEFAULT 0,
    "tour_start_date" "date",
    "tour_end_date" "date",
    "gst_enabled" boolean DEFAULT false,
    "fixed_markup_amount" numeric DEFAULT 0,
    "manual_markup_amount" numeric DEFAULT 0,
    "total_markup_amount" numeric DEFAULT 0,
    "branch_id" "uuid"
);

ALTER TABLE ONLY "public"."quotations" REPLICA IDENTITY FULL;


ALTER TABLE "public"."quotations" OWNER TO "postgres";


COMMENT ON COLUMN "public"."quotations"."fixed_markup_amount" IS 'Fixed markup amount calculated based on company settings percentage';



COMMENT ON COLUMN "public"."quotations"."manual_markup_amount" IS 'Manual markup amount added by user';



COMMENT ON COLUMN "public"."quotations"."total_markup_amount" IS 'Total markup amount (fixed + manual)';



CREATE TABLE IF NOT EXISTS "public"."receipt_sequences" (
    "id" integer DEFAULT 1 NOT NULL,
    "year" integer NOT NULL,
    "next_sequence" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."receipt_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."role_permissions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "role_name" "text" NOT NULL,
    "module_name" "text" NOT NULL,
    "can_view" boolean DEFAULT false NOT NULL,
    "can_create" boolean DEFAULT false NOT NULL,
    "can_edit" boolean DEFAULT false NOT NULL,
    "can_delete" boolean DEFAULT false NOT NULL,
    "can_download" boolean DEFAULT true NOT NULL,
    "can_approve" boolean DEFAULT false NOT NULL,
    "extra_flags" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."role_permissions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."salary_adjustments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payroll_record_id" "uuid" NOT NULL,
    "adjustment_type" "text" NOT NULL,
    "amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "reason" "text" NOT NULL,
    "is_recurring" boolean DEFAULT false,
    "created_by" "uuid" NOT NULL,
    "approved_by" "uuid",
    "approved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "salary_adjustments_adjustment_type_check" CHECK (("adjustment_type" = ANY (ARRAY['bonus'::"text", 'penalty'::"text", 'allowance'::"text", 'deduction'::"text", 'correction'::"text"])))
);


ALTER TABLE "public"."salary_adjustments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."salary_structures" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "component_type" "text" NOT NULL,
    "calculation_type" "text" NOT NULL,
    "amount" numeric(12,2) DEFAULT 0 NOT NULL,
    "is_taxable" boolean DEFAULT true,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "salary_structures_calculation_type_check" CHECK (("calculation_type" = ANY (ARRAY['fixed'::"text", 'percentage'::"text"]))),
    CONSTRAINT "salary_structures_component_type_check" CHECK (("component_type" = ANY (ARRAY['base'::"text", 'allowance'::"text", 'deduction'::"text"])))
);


ALTER TABLE "public"."salary_structures" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_monthly_targets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "staff_id" "uuid" NOT NULL,
    "target_month" "date" NOT NULL,
    "tour_target" integer,
    "pax_target" integer,
    "incentive_percentage" numeric DEFAULT 5.0 NOT NULL,
    "tours_completed" integer DEFAULT 0,
    "pax_completed" integer DEFAULT 0,
    "total_tour_value" numeric DEFAULT 0,
    "tour_target_met" boolean DEFAULT false,
    "pax_target_met" boolean DEFAULT false,
    "targets_achieved" boolean DEFAULT false,
    "incentive_earned" numeric DEFAULT 0,
    "incentive_paid" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."staff_monthly_targets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."staff_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "employee_code" "text" NOT NULL,
    "designation" "text" NOT NULL,
    "department" "text" NOT NULL,
    "date_of_joining" "date" NOT NULL,
    "base_salary" numeric(12,2) DEFAULT 0 NOT NULL,
    "allowances" "jsonb" DEFAULT '{}'::"jsonb",
    "deductions" "jsonb" DEFAULT '{}'::"jsonb",
    "bank_details" "jsonb" DEFAULT '{}'::"jsonb",
    "payment_mode" "text" DEFAULT 'bank_transfer'::"text" NOT NULL,
    "salary_cycle" "text" DEFAULT 'monthly'::"text" NOT NULL,
    "is_commission_eligible" boolean DEFAULT false,
    "incentive_rate" numeric(5,2) DEFAULT 0,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "incentive_enabled" boolean DEFAULT false,
    "monthly_tour_target" integer,
    "monthly_pax_target" integer,
    "incentive_percentage" numeric DEFAULT 5.0
);


ALTER TABLE "public"."staff_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_activity_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "meta" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."task_activity_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_id" "uuid" NOT NULL,
    "author_id" "uuid" NOT NULL,
    "comment" "text" NOT NULL,
    "attachment" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."task_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_id_sequences" (
    "year" integer NOT NULL,
    "next_sequence" integer DEFAULT 1
);


ALTER TABLE "public"."task_id_sequences" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tasks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "task_id" "text" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "assigned_to" "uuid",
    "assigned_by" "uuid",
    "department" "text",
    "priority" "text" DEFAULT 'Medium'::"text",
    "deadline" timestamp with time zone,
    "status" "text" DEFAULT 'Pending'::"text",
    "completion_at" timestamp with time zone,
    "related_booking_id" "uuid",
    "attachments" "jsonb" DEFAULT '[]'::"jsonb",
    "quality_rating" numeric,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "branch_id" "uuid",
    "assigned_at" timestamp with time zone,
    CONSTRAINT "tasks_priority_check" CHECK (("priority" = ANY (ARRAY['High'::"text", 'Medium'::"text", 'Low'::"text"]))),
    CONSTRAINT "tasks_quality_rating_check" CHECK ((("quality_rating" >= (1)::numeric) AND ("quality_rating" <= (5)::numeric))),
    CONSTRAINT "tasks_status_check" CHECK (("status" = ANY (ARRAY['Pending'::"text", 'In Progress'::"text", 'Completed'::"text", 'Delayed'::"text"])))
);


ALTER TABLE "public"."tasks" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tasks"."assigned_at" IS 'Timestamp when task was explicitly assigned';



CREATE TABLE IF NOT EXISTS "public"."tour_package_fixed_pricing" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tour_package_id" "uuid" NOT NULL,
    "pax_range" "text" NOT NULL,
    "adult_price" numeric NOT NULL,
    "child_price" numeric NOT NULL,
    "infant_price" numeric NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."tour_package_fixed_pricing" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tour_packages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "price_per_adult" numeric,
    "price_per_child" numeric,
    "itinerary" "jsonb" DEFAULT '[]'::"jsonb",
    "inclusions" "text",
    "exclusions" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "duration_days" integer,
    "duration_nights" integer,
    "category" "text" DEFAULT 'customized'::"text",
    "group_tour_dates" "jsonb" DEFAULT '[]'::"jsonb",
    "total_food_price" numeric,
    "staff_ticket_price" numeric,
    "hotel_details" "jsonb" DEFAULT '[]'::"jsonb",
    "company_name" "text",
    "no_of_travellers" integer,
    "notes" "text",
    "cost_per_person" numeric,
    "cost_currency" "text" DEFAULT 'INR'::"text",
    "travel_date_from" "date",
    "travel_date_to" "date",
    "destination" "text",
    "pickup_point" "text",
    "drop_point" "text",
    "price_per_infant" numeric,
    "tour_category" "text",
    "validity_from" "date",
    "validity_to" "date",
    "branch_region_tag" "text",
    "package_id" "text",
    "is_duplicate" boolean DEFAULT false
);

ALTER TABLE ONLY "public"."tour_packages" REPLICA IDENTITY FULL;


ALTER TABLE "public"."tour_packages" OWNER TO "postgres";


COMMENT ON COLUMN "public"."tour_packages"."is_duplicate" IS 'Indicates if this package is a duplicate copy that has not been edited yet';



CREATE TABLE IF NOT EXISTS "public"."user_roles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."app_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid"
);


ALTER TABLE "public"."user_roles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vendor_locations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vendor_id" "uuid" NOT NULL,
    "location_name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."vendor_locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vendor_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vendor_id" "uuid" NOT NULL,
    "booking_vendor_item_id" "uuid",
    "direction" "text" NOT NULL,
    "amount" numeric NOT NULL,
    "note" "text",
    "paid_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "vendor_payments_direction_check" CHECK (("direction" = ANY (ARRAY['admin_to_vendor'::"text", 'vendor_to_admin'::"text", 'adjustment'::"text"])))
);


ALTER TABLE "public"."vendor_payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vendors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "type" "text" NOT NULL,
    "location" "text" NOT NULL,
    "contact_person" "text",
    "phone" "text",
    "email" "text",
    "address" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid" NOT NULL,
    "contact_no" "text",
    "service_locations" "text"[],
    CONSTRAINT "vendors_type_check" CHECK (("type" = ANY (ARRAY['hotel'::"text", 'car'::"text", 'dmc'::"text"])))
);

ALTER TABLE ONLY "public"."vendors" REPLICA IDENTITY FULL;


ALTER TABLE "public"."vendors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."yellow_app_sync_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sync_type" "text" NOT NULL,
    "sync_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "records_count" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "last_sync_id" "text",
    "error_log" "jsonb" DEFAULT '{}'::"jsonb",
    "sync_data" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "yellow_app_sync_log_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'success'::"text", 'failed'::"text", 'partial'::"text"]))),
    CONSTRAINT "yellow_app_sync_log_sync_type_check" CHECK (("sync_type" = ANY (ARRAY['attendance'::"text", 'booking'::"text", 'leave'::"text", 'commission'::"text"])))
);


ALTER TABLE "public"."yellow_app_sync_log" OWNER TO "postgres";


ALTER TABLE ONLY "public"."cancellation_invoice_sequences" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cancellation_invoice_sequences_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."invoice_non_gst_sequences" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."invoice_non_gst_sequences_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."invoice_sequences" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."invoice_sequences_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."access_audit_log"
    ADD CONSTRAINT "access_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_profiles"
    ADD CONSTRAINT "agent_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."agent_profiles"
    ADD CONSTRAINT "agent_profiles_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."api_access_log"
    ADD CONSTRAINT "api_access_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_notification_recipients"
    ADD CONSTRAINT "app_notification_recipients_notification_id_user_id_key" UNIQUE ("notification_id", "user_id");



ALTER TABLE ONLY "public"."app_notification_recipients"
    ADD CONSTRAINT "app_notification_recipients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."app_notifications"
    ADD CONSTRAINT "app_notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_shifts"
    ADD CONSTRAINT "attendance_shifts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."attendance_submissions"
    ADD CONSTRAINT "attendance_submissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_approval_requests"
    ADD CONSTRAINT "booking_approval_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."booking_id_sequences"
    ADD CONSTRAINT "booking_id_sequences_pkey" PRIMARY KEY ("year");



ALTER TABLE ONLY "public"."booking_vendor_items"
    ADD CONSTRAINT "booking_vendor_items_booking_id_vendor_id_service_type_key" UNIQUE ("booking_id", "vendor_id", "service_type");



ALTER TABLE ONLY "public"."booking_vendor_items"
    ADD CONSTRAINT "booking_vendor_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_booking_id_key" UNIQUE ("booking_id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branch_audit_log"
    ADD CONSTRAINT "branch_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cancellation_invoice_sequences"
    ADD CONSTRAINT "cancellation_invoice_sequences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cancellation_invoice_sequences"
    ADD CONSTRAINT "cancellation_invoice_sequences_year_key" UNIQUE ("year");



ALTER TABLE ONLY "public"."car_rate_lists"
    ADD CONSTRAINT "car_rate_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."car_rate_rows"
    ADD CONSTRAINT "car_rate_rows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."car_rate_seasons"
    ADD CONSTRAINT "car_rate_seasons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commission_records"
    ADD CONSTRAINT "commission_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."company_settings"
    ADD CONSTRAINT "company_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."deletion_requests"
    ADD CONSTRAINT "deletion_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_user_id_device_id_key" UNIQUE ("user_id", "device_id");



ALTER TABLE ONLY "public"."dmc_vendor_packages"
    ADD CONSTRAINT "dmc_vendor_packages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dmc_vendor_packages"
    ADD CONSTRAINT "dmc_vendor_packages_tour_package_id_key" UNIQUE ("tour_package_id");



ALTER TABLE ONLY "public"."employee_code_sequences"
    ADD CONSTRAINT "employee_code_sequences_pkey" PRIMARY KEY ("year");



ALTER TABLE ONLY "public"."expense_bookings"
    ADD CONSTRAINT "expense_bookings_expense_id_booking_id_key" UNIQUE ("expense_id", "booking_id");



ALTER TABLE ONLY "public"."expense_bookings"
    ADD CONSTRAINT "expense_bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_tour_capacity_audit"
    ADD CONSTRAINT "group_tour_capacity_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_tour_dates"
    ADD CONSTRAINT "group_tour_dates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hotel_rate_lists"
    ADD CONSTRAINT "hotel_rate_lists_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hotel_rate_rows"
    ADD CONSTRAINT "hotel_rate_rows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."hotel_rate_seasons"
    ADD CONSTRAINT "hotel_rate_seasons_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."incentive_records"
    ADD CONSTRAINT "incentive_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_approval_requests"
    ADD CONSTRAINT "invoice_approval_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_cancellations"
    ADD CONSTRAINT "invoice_cancellations_original_invoice_id_key" UNIQUE ("original_invoice_id");



ALTER TABLE ONLY "public"."invoice_cancellations"
    ADD CONSTRAINT "invoice_cancellations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_non_gst_sequences"
    ADD CONSTRAINT "invoice_non_gst_sequences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_payments"
    ADD CONSTRAINT "invoice_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoice_sequences"
    ADD CONSTRAINT "invoice_sequences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."kpi_scores"
    ADD CONSTRAINT "kpi_scores_employee_id_period_start_period_end_key" UNIQUE ("employee_id", "period_start", "period_end");



ALTER TABLE ONLY "public"."kpi_scores"
    ADD CONSTRAINT "kpi_scores_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lead_activities"
    ADD CONSTRAINT "lead_activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."lead_details"
    ADD CONSTRAINT "lead_details_pkey" PRIMARY KEY ("lead_id");



ALTER TABLE ONLY "public"."lead_id_sequences"
    ADD CONSTRAINT "lead_id_sequences_pkey" PRIMARY KEY ("year");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_lead_id_key" UNIQUE ("lead_id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."module_permissions"
    ADD CONSTRAINT "module_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."module_permissions"
    ADD CONSTRAINT "module_permissions_role_module_name_key" UNIQUE ("role", "module_name");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."office_geofences"
    ADD CONSTRAINT "office_geofences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."package_id_sequences"
    ADD CONSTRAINT "package_id_sequences_pkey" PRIMARY KEY ("category");



ALTER TABLE ONLY "public"."payroll_deductions"
    ADD CONSTRAINT "payroll_deductions_payroll_record_id_unique" UNIQUE ("payroll_record_id");



ALTER TABLE ONLY "public"."payroll_deductions"
    ADD CONSTRAINT "payroll_deductions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payroll_earnings"
    ADD CONSTRAINT "payroll_earnings_payroll_record_id_unique" UNIQUE ("payroll_record_id");



ALTER TABLE ONLY "public"."payroll_earnings"
    ADD CONSTRAINT "payroll_earnings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payroll_records"
    ADD CONSTRAINT "payroll_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payroll_records"
    ADD CONSTRAINT "payroll_records_staff_id_pay_period_start_pay_period_end_key" UNIQUE ("staff_id", "pay_period_start", "pay_period_end");



ALTER TABLE ONLY "public"."petty_cash_ledger"
    ADD CONSTRAINT "petty_cash_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotation_markup_settings"
    ADD CONSTRAINT "quotation_markup_settings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotations"
    ADD CONSTRAINT "quotations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."receipt_sequences"
    ADD CONSTRAINT "receipt_sequences_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."receipt_sequences"
    ADD CONSTRAINT "receipt_sequences_year_key" UNIQUE ("year");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."role_permissions"
    ADD CONSTRAINT "role_permissions_role_name_module_name_key" UNIQUE ("role_name", "module_name");



ALTER TABLE ONLY "public"."salary_adjustments"
    ADD CONSTRAINT "salary_adjustments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."salary_structures"
    ADD CONSTRAINT "salary_structures_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_monthly_targets"
    ADD CONSTRAINT "staff_monthly_targets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."staff_monthly_targets"
    ADD CONSTRAINT "staff_monthly_targets_staff_id_target_month_key" UNIQUE ("staff_id", "target_month");



ALTER TABLE ONLY "public"."staff_profiles"
    ADD CONSTRAINT "staff_profiles_employee_code_key" UNIQUE ("employee_code");



ALTER TABLE ONLY "public"."staff_profiles"
    ADD CONSTRAINT "staff_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_activity_log"
    ADD CONSTRAINT "task_activity_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_comments"
    ADD CONSTRAINT "task_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_id_sequences"
    ADD CONSTRAINT "task_id_sequences_pkey" PRIMARY KEY ("year");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_task_id_key" UNIQUE ("task_id");



ALTER TABLE ONLY "public"."tour_package_fixed_pricing"
    ADD CONSTRAINT "tour_package_fixed_pricing_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tour_packages"
    ADD CONSTRAINT "tour_packages_package_id_key" UNIQUE ("package_id");



ALTER TABLE ONLY "public"."tour_packages"
    ADD CONSTRAINT "tour_packages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."group_tour_dates"
    ADD CONSTRAINT "unique_package_date" UNIQUE ("package_id", "travel_date");



ALTER TABLE ONLY "public"."attendance_shifts"
    ADD CONSTRAINT "unique_user_active_shift" UNIQUE ("user_id", "active");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_email_unique" UNIQUE ("email");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_role_key" UNIQUE ("user_id", "role");



ALTER TABLE ONLY "public"."vendor_locations"
    ADD CONSTRAINT "vendor_locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vendor_payments"
    ADD CONSTRAINT "vendor_payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vendors"
    ADD CONSTRAINT "vendors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."yellow_app_sync_log"
    ADD CONSTRAINT "yellow_app_sync_log_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_agent_profiles_user_id" ON "public"."agent_profiles" USING "btree" ("user_id");



CREATE INDEX "idx_api_log_endpoint" ON "public"."api_access_log" USING "btree" ("endpoint", "created_at");



CREATE INDEX "idx_api_log_user_date" ON "public"."api_access_log" USING "btree" ("user_id", "created_at");



CREATE INDEX "idx_app_notification_recipients_user" ON "public"."app_notification_recipients" USING "btree" ("user_id");



CREATE INDEX "idx_app_notifications_created_at" ON "public"."app_notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_app_notifications_scheduled" ON "public"."app_notifications" USING "btree" ("scheduled_for") WHERE ("status" = 'scheduled'::"text");



CREATE INDEX "idx_app_notifications_status" ON "public"."app_notifications" USING "btree" ("status");



CREATE INDEX "idx_attendance_branch_date" ON "public"."attendance_records" USING "btree" ("branch_id", "attendance_date");



CREATE INDEX "idx_attendance_branch_id" ON "public"."attendance_records" USING "btree" ("branch_id");



CREATE INDEX "idx_attendance_branch_status" ON "public"."attendance_records" USING "btree" ("branch_id", "status");



CREATE INDEX "idx_attendance_date_status" ON "public"."attendance_records" USING "btree" ("attendance_date", "status");



CREATE INDEX "idx_attendance_employee_date" ON "public"."attendance_records" USING "btree" ("employee_id", "attendance_date");



CREATE INDEX "idx_attendance_records_date" ON "public"."attendance_records" USING "btree" ("attendance_date");



CREATE INDEX "idx_attendance_records_employee_id" ON "public"."attendance_records" USING "btree" ("employee_id");



CREATE INDEX "idx_attendance_records_status" ON "public"."attendance_records" USING "btree" ("status");



CREATE INDEX "idx_attendance_shifts_active" ON "public"."attendance_shifts" USING "btree" ("active");



CREATE INDEX "idx_attendance_shifts_branch_id" ON "public"."attendance_shifts" USING "btree" ("branch_id");



CREATE INDEX "idx_attendance_shifts_user_id" ON "public"."attendance_shifts" USING "btree" ("user_id");



CREATE INDEX "idx_attendance_status" ON "public"."attendance_records" USING "btree" ("status");



CREATE INDEX "idx_audit_booking" ON "public"."group_tour_capacity_audit" USING "btree" ("booking_id");



CREATE INDEX "idx_audit_date" ON "public"."group_tour_capacity_audit" USING "btree" ("group_tour_date_id");



CREATE INDEX "idx_booking_approval_requests_booking_id" ON "public"."booking_approval_requests" USING "btree" ("booking_id");



CREATE INDEX "idx_booking_approval_requests_requested_by" ON "public"."booking_approval_requests" USING "btree" ("requested_by");



CREATE INDEX "idx_booking_approval_requests_status" ON "public"."booking_approval_requests" USING "btree" ("status");



CREATE INDEX "idx_booking_vendor_items_booking_id" ON "public"."booking_vendor_items" USING "btree" ("booking_id");



CREATE INDEX "idx_booking_vendor_items_vendor_id" ON "public"."booking_vendor_items" USING "btree" ("vendor_id");



CREATE INDEX "idx_bookings_assigned_to" ON "public"."bookings" USING "btree" ("assigned_to");



CREATE INDEX "idx_bookings_assigned_to_assigned_at" ON "public"."bookings" USING "btree" ("assigned_to", "assigned_at");



CREATE INDEX "idx_bookings_branch_id" ON "public"."bookings" USING "btree" ("branch_id");



CREATE INDEX "idx_bookings_created_at" ON "public"."bookings" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_bookings_created_by" ON "public"."bookings" USING "btree" ("created_by");



CREATE INDEX "idx_bookings_group_tour_date" ON "public"."bookings" USING "btree" ("group_tour_date_id");



CREATE INDEX "idx_bookings_referred_by" ON "public"."bookings" USING "btree" ("referred_by_id");



CREATE INDEX "idx_bookings_referred_by_id" ON "public"."bookings" USING "btree" ("referred_by_id");



CREATE INDEX "idx_bookings_travel_start_date" ON "public"."bookings" USING "btree" ("travel_start_date");



CREATE INDEX "idx_branch_audit_branch_id" ON "public"."branch_audit_log" USING "btree" ("branch_id");



CREATE INDEX "idx_branch_audit_performed_by" ON "public"."branch_audit_log" USING "btree" ("performed_by");



CREATE INDEX "idx_branch_audit_timestamp" ON "public"."branch_audit_log" USING "btree" ("timestamp" DESC);



CREATE UNIQUE INDEX "idx_branches_location_unique" ON "public"."branches" USING "btree" ("location") WHERE ("active" = true);



CREATE INDEX "idx_commission_staff_status" ON "public"."commission_records" USING "btree" ("staff_id", "status");



CREATE INDEX "idx_expense_bookings_booking_id" ON "public"."expense_bookings" USING "btree" ("booking_id");



CREATE INDEX "idx_expense_bookings_expense_id" ON "public"."expense_bookings" USING "btree" ("expense_id");



CREATE INDEX "idx_expenses_branch_id" ON "public"."expenses" USING "btree" ("branch_id");



CREATE INDEX "idx_expenses_expense_type" ON "public"."expenses" USING "btree" ("expense_type");



CREATE INDEX "idx_expenses_group_id" ON "public"."expenses" USING "btree" ("group_id");



CREATE INDEX "idx_fixed_pricing_package_id" ON "public"."tour_package_fixed_pricing" USING "btree" ("tour_package_id");



CREATE INDEX "idx_group_tour_dates_capacity" ON "public"."group_tour_dates" USING "btree" ("capacity_remaining") WHERE ("capacity_remaining" > 0);



CREATE INDEX "idx_group_tour_dates_package" ON "public"."group_tour_dates" USING "btree" ("package_id");



CREATE INDEX "idx_group_tour_dates_travel_date" ON "public"."group_tour_dates" USING "btree" ("travel_date");



CREATE INDEX "idx_hotel_rate_lists_active" ON "public"."hotel_rate_lists" USING "btree" ("active");



CREATE INDEX "idx_hotel_rate_lists_vendor_id" ON "public"."hotel_rate_lists" USING "btree" ("vendor_id");



CREATE INDEX "idx_hotel_rate_rows_season_id" ON "public"."hotel_rate_rows" USING "btree" ("season_id");



CREATE INDEX "idx_hotel_rate_seasons_dates" ON "public"."hotel_rate_seasons" USING "btree" ("start_date", "end_date");



CREATE INDEX "idx_hotel_rate_seasons_rate_list_id" ON "public"."hotel_rate_seasons" USING "btree" ("rate_list_id");



CREATE INDEX "idx_invoice_approval_invoice_id" ON "public"."invoice_approval_requests" USING "btree" ("invoice_id");



CREATE INDEX "idx_invoice_approval_requested_by" ON "public"."invoice_approval_requests" USING "btree" ("requested_by");



CREATE INDEX "idx_invoice_approval_status" ON "public"."invoice_approval_requests" USING "btree" ("status");



CREATE INDEX "idx_invoice_payments_invoice" ON "public"."invoice_payments" USING "btree" ("invoice_id");



CREATE INDEX "idx_invoice_payments_paid_on" ON "public"."invoice_payments" USING "btree" ("paid_on");



CREATE INDEX "idx_invoice_payments_payee" ON "public"."invoice_payments" USING "btree" ("payee_type", "payee_id");



CREATE INDEX "idx_invoices_booking_id" ON "public"."invoices" USING "btree" ("booking_id");



CREATE INDEX "idx_invoices_branch_id" ON "public"."invoices" USING "btree" ("branch_id");



CREATE INDEX "idx_invoices_created_at" ON "public"."invoices" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_invoices_created_by" ON "public"."invoices" USING "btree" ("created_by");



CREATE INDEX "idx_invoices_pending_amount" ON "public"."invoices" USING "btree" ("pending_amount") WHERE ("pending_amount" > (0)::numeric);



CREATE INDEX "idx_invoices_status" ON "public"."invoices" USING "btree" ("status");



CREATE INDEX "idx_kpi_scores_employee_id" ON "public"."kpi_scores" USING "btree" ("employee_id");



CREATE INDEX "idx_kpi_scores_period" ON "public"."kpi_scores" USING "btree" ("period_start", "period_end");



CREATE INDEX "idx_leads_assigned_to" ON "public"."leads" USING "btree" ("assigned_to");



CREATE INDEX "idx_leads_assigned_to_assigned_at" ON "public"."leads" USING "btree" ("assigned_to", "assigned_at");



CREATE INDEX "idx_leads_branch_id" ON "public"."leads" USING "btree" ("branch_id");



CREATE INDEX "idx_leads_created_at" ON "public"."leads" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_leads_created_by" ON "public"."leads" USING "btree" ("created_by");



CREATE INDEX "idx_leads_follow_up_date" ON "public"."leads" USING "btree" ("follow_up_date");



CREATE INDEX "idx_leads_temperature_tag" ON "public"."leads" USING "btree" ("temperature_tag");



CREATE INDEX "idx_leave_requests_employee_id" ON "public"."leave_requests" USING "btree" ("employee_id");



CREATE INDEX "idx_leave_requests_status" ON "public"."leave_requests" USING "btree" ("status");



CREATE INDEX "idx_notifications_created_at" ON "public"."notifications" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_notifications_user_id" ON "public"."notifications" USING "btree" ("user_id");



CREATE INDEX "idx_payroll_deductions_record_id" ON "public"."payroll_deductions" USING "btree" ("payroll_record_id");



CREATE INDEX "idx_payroll_earnings_record_id" ON "public"."payroll_earnings" USING "btree" ("payroll_record_id");



CREATE INDEX "idx_quotations_branch_id" ON "public"."quotations" USING "btree" ("branch_id");



CREATE INDEX "idx_quotations_created_at" ON "public"."quotations" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_quotations_created_by" ON "public"."quotations" USING "btree" ("created_by");



CREATE INDEX "idx_staff_monthly_targets_achieved" ON "public"."staff_monthly_targets" USING "btree" ("targets_achieved", "incentive_paid") WHERE ("targets_achieved" = true);



CREATE INDEX "idx_staff_monthly_targets_staff_month" ON "public"."staff_monthly_targets" USING "btree" ("staff_id", "target_month");



CREATE INDEX "idx_submissions_date" ON "public"."attendance_submissions" USING "btree" ("submitted_at");



CREATE INDEX "idx_submissions_employee" ON "public"."attendance_submissions" USING "btree" ("employee_id");



CREATE INDEX "idx_submissions_record_id" ON "public"."attendance_submissions" USING "btree" ("attendance_record_id");



CREATE INDEX "idx_submissions_status" ON "public"."attendance_submissions" USING "btree" ("status");



CREATE INDEX "idx_task_activity_log_task_id" ON "public"."task_activity_log" USING "btree" ("task_id");



CREATE INDEX "idx_task_comments_task_id" ON "public"."task_comments" USING "btree" ("task_id");



CREATE INDEX "idx_tasks_assigned_to" ON "public"."tasks" USING "btree" ("assigned_to");



CREATE INDEX "idx_tasks_assigned_to_assigned_at" ON "public"."tasks" USING "btree" ("assigned_to", "assigned_at");



CREATE INDEX "idx_tasks_branch_id" ON "public"."tasks" USING "btree" ("branch_id");



CREATE INDEX "idx_tasks_deadline" ON "public"."tasks" USING "btree" ("deadline");



CREATE INDEX "idx_tasks_status" ON "public"."tasks" USING "btree" ("status");



CREATE INDEX "idx_user_profiles_email" ON "public"."user_profiles" USING "btree" ("email");



CREATE INDEX "idx_user_profiles_is_active" ON "public"."user_profiles" USING "btree" ("is_active");



CREATE INDEX "idx_user_profiles_user_id" ON "public"."user_profiles" USING "btree" ("user_id");



COMMENT ON INDEX "public"."idx_user_profiles_user_id" IS 'Improves authentication performance for profile lookups';



CREATE INDEX "idx_user_profiles_user_id_role" ON "public"."user_profiles" USING "btree" ("user_id", "role");



COMMENT ON INDEX "public"."idx_user_profiles_user_id_role" IS 'Optimizes combined user_id + role queries';



CREATE INDEX "idx_user_roles_role" ON "public"."user_roles" USING "btree" ("role");



CREATE INDEX "idx_user_roles_user_id" ON "public"."user_roles" USING "btree" ("user_id");



COMMENT ON INDEX "public"."idx_user_roles_user_id" IS 'Improves authentication performance for role lookups';



CREATE INDEX "idx_vendor_locations_vendor_id" ON "public"."vendor_locations" USING "btree" ("vendor_id");



CREATE INDEX "idx_vendor_payments_booking_vendor_item_id" ON "public"."vendor_payments" USING "btree" ("booking_vendor_item_id");



CREATE INDEX "idx_vendor_payments_vendor_id" ON "public"."vendor_payments" USING "btree" ("vendor_id");



CREATE UNIQUE INDEX "ux_user_profiles_user_id" ON "public"."user_profiles" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "app_set_notifications_updated_at" BEFORE UPDATE ON "public"."app_notifications" FOR EACH ROW EXECUTE FUNCTION "public"."app_handle_updated_at"();



CREATE OR REPLACE TRIGGER "assign_booking_id_trigger" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."assign_booking_id"();



CREATE OR REPLACE TRIGGER "assign_package_id_trigger" BEFORE INSERT ON "public"."tour_packages" FOR EACH ROW EXECUTE FUNCTION "public"."assign_package_id"();



CREATE OR REPLACE TRIGGER "auto_create_booking_commission" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."auto_create_commission_record"();



CREATE OR REPLACE TRIGGER "notify_new_booking_trigger" AFTER INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."notify_new_booking"();



CREATE OR REPLACE TRIGGER "notify_new_followup_trigger" AFTER INSERT ON "public"."lead_activities" FOR EACH ROW EXECUTE FUNCTION "public"."notify_new_followup"();



CREATE OR REPLACE TRIGGER "notify_new_lead_trigger" AFTER INSERT ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."notify_new_lead"();



CREATE OR REPLACE TRIGGER "on_agent_role_assigned" AFTER INSERT OR UPDATE ON "public"."user_roles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_agent_role_assignment"();



CREATE OR REPLACE TRIGGER "set_booking_branch_id_trigger" BEFORE INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."set_booking_branch_id"();



CREATE OR REPLACE TRIGGER "set_expense_branch_id_trigger" BEFORE INSERT ON "public"."expenses" FOR EACH ROW EXECUTE FUNCTION "public"."set_expense_branch_id"();



CREATE OR REPLACE TRIGGER "set_invoice_id" BEFORE INSERT ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."assign_invoice_id"();



CREATE OR REPLACE TRIGGER "sync_user_roles_trigger" AFTER INSERT OR UPDATE OF "role" ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_user_roles"();



CREATE OR REPLACE TRIGGER "task_activity_trigger" AFTER INSERT OR UPDATE ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."log_task_activity"();



CREATE OR REPLACE TRIGGER "track_staff_tour_completion" AFTER UPDATE ON "public"."bookings" FOR EACH ROW WHEN (("old"."booking_status" IS DISTINCT FROM "new"."booking_status")) EXECUTE FUNCTION "public"."update_staff_monthly_target"();



CREATE OR REPLACE TRIGGER "trigger_assign_lead_id" BEFORE INSERT ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."assign_lead_id"();



CREATE OR REPLACE TRIGGER "trigger_assign_task_id" BEFORE INSERT ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."assign_task_id"();



CREATE OR REPLACE TRIGGER "trigger_bookings_assigned_at" BEFORE UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_assigned_at"();



CREATE OR REPLACE TRIGGER "trigger_compute_attendance_status" BEFORE INSERT OR UPDATE ON "public"."attendance_records" FOR EACH ROW EXECUTE FUNCTION "public"."compute_attendance_status"();



CREATE OR REPLACE TRIGGER "trigger_create_agent_commission" AFTER INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."create_agent_commission_on_booking"();



CREATE OR REPLACE TRIGGER "trigger_create_agent_profile" AFTER INSERT ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."create_agent_profile"();



CREATE OR REPLACE TRIGGER "trigger_leads_assigned_at" BEFORE UPDATE ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."update_assigned_at"();



CREATE OR REPLACE TRIGGER "trigger_set_cancellation_invoice_id" BEFORE INSERT ON "public"."invoice_cancellations" FOR EACH ROW EXECUTE FUNCTION "public"."set_cancellation_invoice_id"();



CREATE OR REPLACE TRIGGER "trigger_tasks_assigned_at" BEFORE UPDATE ON "public"."tasks" FOR EACH ROW EXECUTE FUNCTION "public"."update_assigned_at"();



CREATE OR REPLACE TRIGGER "trigger_update_agent_stats" AFTER INSERT OR UPDATE ON "public"."bookings" FOR EACH ROW WHEN (("new"."booking_status" = 'Confirmed'::"text")) EXECUTE FUNCTION "public"."update_agent_stats"();



CREATE OR REPLACE TRIGGER "trigger_update_commission_on_completion" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_commission_on_tour_completion"();



CREATE OR REPLACE TRIGGER "trigger_update_staff_targets" AFTER INSERT OR UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_staff_monthly_targets_on_booking"();



CREATE OR REPLACE TRIGGER "update_agent_profiles_updated_at" BEFORE UPDATE ON "public"."agent_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_attendance_shifts_updated_at" BEFORE UPDATE ON "public"."attendance_shifts" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_attendance_submission_timestamp" BEFORE UPDATE ON "public"."attendance_submissions" FOR EACH ROW EXECUTE FUNCTION "public"."update_attendance_submission_timestamp"();



CREATE OR REPLACE TRIGGER "update_booking_vendor_items_updated_at" BEFORE UPDATE ON "public"."booking_vendor_items" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_bookings_updated_at" BEFORE UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_branches_updated_at" BEFORE UPDATE ON "public"."branches" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_car_rate_lists_updated_at" BEFORE UPDATE ON "public"."car_rate_lists" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_car_rate_rows_updated_at" BEFORE UPDATE ON "public"."car_rate_rows" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_car_rate_seasons_updated_at" BEFORE UPDATE ON "public"."car_rate_seasons" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_commission_records_updated_at" BEFORE UPDATE ON "public"."commission_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_company_settings_updated_at" BEFORE UPDATE ON "public"."company_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_dmc_vendor_packages_updated_at" BEFORE UPDATE ON "public"."dmc_vendor_packages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_expenses_updated_at" BEFORE UPDATE ON "public"."expenses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_hotel_rate_lists_updated_at" BEFORE UPDATE ON "public"."hotel_rate_lists" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_hotel_rate_rows_updated_at" BEFORE UPDATE ON "public"."hotel_rate_rows" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_hotel_rate_seasons_updated_at" BEFORE UPDATE ON "public"."hotel_rate_seasons" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_incentive_records_updated_at" BEFORE UPDATE ON "public"."incentive_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_invoice_approval_requests_updated_at" BEFORE UPDATE ON "public"."invoice_approval_requests" FOR EACH ROW EXECUTE FUNCTION "public"."update_invoice_approval_updated_at"();



CREATE OR REPLACE TRIGGER "update_invoices_updated_at" BEFORE UPDATE ON "public"."invoices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_leads_updated_at" BEFORE UPDATE ON "public"."leads" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_payroll_deductions_updated_at" BEFORE UPDATE ON "public"."payroll_deductions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_payroll_earnings_updated_at" BEFORE UPDATE ON "public"."payroll_earnings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_payroll_records_updated_at" BEFORE UPDATE ON "public"."payroll_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_petty_cash_ledger_updated_at" BEFORE UPDATE ON "public"."petty_cash_ledger" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_quotation_markup_settings_updated_at" BEFORE UPDATE ON "public"."quotation_markup_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_quotations_updated_at" BEFORE UPDATE ON "public"."quotations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_salary_adjustments_updated_at" BEFORE UPDATE ON "public"."salary_adjustments" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_salary_structures_updated_at" BEFORE UPDATE ON "public"."salary_structures" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_staff_profiles_updated_at" BEFORE UPDATE ON "public"."staff_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_tour_package_fixed_pricing_updated_at" BEFORE UPDATE ON "public"."tour_package_fixed_pricing" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_tour_packages_updated_at" BEFORE UPDATE ON "public"."tour_packages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_vendor_locations_updated_at" BEFORE UPDATE ON "public"."vendor_locations" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_vendors_updated_at" BEFORE UPDATE ON "public"."vendors" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_yellow_app_sync_log_updated_at" BEFORE UPDATE ON "public"."yellow_app_sync_log" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "validate_profile_has_auth" BEFORE INSERT ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."validate_user_profile_auth"();



ALTER TABLE ONLY "public"."access_audit_log"
    ADD CONSTRAINT "access_audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."api_access_log"
    ADD CONSTRAINT "api_access_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_notification_recipients"
    ADD CONSTRAINT "app_notification_recipients_notification_id_fkey" FOREIGN KEY ("notification_id") REFERENCES "public"."app_notifications"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_notification_recipients"
    ADD CONSTRAINT "app_notification_recipients_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."app_notifications"
    ADD CONSTRAINT "app_notifications_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_notifications"
    ADD CONSTRAINT "app_notifications_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."user_profiles"("user_id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."attendance_records"
    ADD CONSTRAINT "attendance_records_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."attendance_shifts"
    ADD CONSTRAINT "attendance_shifts_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance_shifts"
    ADD CONSTRAINT "attendance_shifts_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."attendance_shifts"
    ADD CONSTRAINT "attendance_shifts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_submissions"
    ADD CONSTRAINT "attendance_submissions_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "public"."user_profiles"("user_id");



ALTER TABLE ONLY "public"."attendance_submissions"
    ADD CONSTRAINT "attendance_submissions_attendance_record_id_fkey" FOREIGN KEY ("attendance_record_id") REFERENCES "public"."attendance_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."attendance_submissions"
    ADD CONSTRAINT "attendance_submissions_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."user_profiles"("user_id");



ALTER TABLE ONLY "public"."booking_approval_requests"
    ADD CONSTRAINT "booking_approval_requests_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_approval_requests"
    ADD CONSTRAINT "booking_approval_requests_requested_by_fkey" FOREIGN KEY ("requested_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."booking_approval_requests"
    ADD CONSTRAINT "booking_approval_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."booking_vendor_items"
    ADD CONSTRAINT "booking_vendor_items_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."booking_vendor_items"
    ADD CONSTRAINT "booking_vendor_items_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "public"."vendors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_dmc_vendor_id_fkey" FOREIGN KEY ("dmc_vendor_id") REFERENCES "public"."vendors"("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_group_tour_date_id_fkey" FOREIGN KEY ("group_tour_date_id") REFERENCES "public"."group_tour_dates"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_audit_log"
    ADD CONSTRAINT "branch_audit_log_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."branch_audit_log"
    ADD CONSTRAINT "branch_audit_log_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."branches"
    ADD CONSTRAINT "branches_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."car_rate_lists"
    ADD CONSTRAINT "car_rate_lists_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."commission_records"
    ADD CONSTRAINT "commission_records_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."commission_records"
    ADD CONSTRAINT "commission_records_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."commission_records"
    ADD CONSTRAINT "commission_records_payroll_record_id_fkey" FOREIGN KEY ("payroll_record_id") REFERENCES "public"."payroll_records"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."company_settings"
    ADD CONSTRAINT "company_settings_updated_by_fkey" FOREIGN KEY ("updated_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."deletion_requests"
    ADD CONSTRAINT "deletion_requests_requester_id_fkey" FOREIGN KEY ("requester_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."deletion_requests"
    ADD CONSTRAINT "deletion_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."device_sessions"
    ADD CONSTRAINT "device_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."dmc_vendor_packages"
    ADD CONSTRAINT "dmc_vendor_packages_dmc_vendor_id_fkey" FOREIGN KEY ("dmc_vendor_id") REFERENCES "public"."vendors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dmc_vendor_packages"
    ADD CONSTRAINT "dmc_vendor_packages_tour_package_id_fkey" FOREIGN KEY ("tour_package_id") REFERENCES "public"."tour_packages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_bookings"
    ADD CONSTRAINT "expense_bookings_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expense_bookings"
    ADD CONSTRAINT "expense_bookings_expense_id_fkey" FOREIGN KEY ("expense_id") REFERENCES "public"."expenses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."expenses"
    ADD CONSTRAINT "expenses_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "public"."vendors"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."group_tour_capacity_audit"
    ADD CONSTRAINT "group_tour_capacity_audit_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."group_tour_capacity_audit"
    ADD CONSTRAINT "group_tour_capacity_audit_changed_by_fkey" FOREIGN KEY ("changed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."group_tour_capacity_audit"
    ADD CONSTRAINT "group_tour_capacity_audit_group_tour_date_id_fkey" FOREIGN KEY ("group_tour_date_id") REFERENCES "public"."group_tour_dates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."group_tour_dates"
    ADD CONSTRAINT "group_tour_dates_package_id_fkey" FOREIGN KEY ("package_id") REFERENCES "public"."tour_packages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hotel_rate_lists"
    ADD CONSTRAINT "hotel_rate_lists_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hotel_rate_lists"
    ADD CONSTRAINT "hotel_rate_lists_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "public"."vendors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hotel_rate_rows"
    ADD CONSTRAINT "hotel_rate_rows_season_id_fkey" FOREIGN KEY ("season_id") REFERENCES "public"."hotel_rate_seasons"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."hotel_rate_seasons"
    ADD CONSTRAINT "hotel_rate_seasons_rate_list_id_fkey" FOREIGN KEY ("rate_list_id") REFERENCES "public"."hotel_rate_lists"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."incentive_records"
    ADD CONSTRAINT "incentive_records_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."incentive_records"
    ADD CONSTRAINT "incentive_records_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."incentive_records"
    ADD CONSTRAINT "incentive_records_payroll_record_id_fkey" FOREIGN KEY ("payroll_record_id") REFERENCES "public"."payroll_records"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."incentive_records"
    ADD CONSTRAINT "incentive_records_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoice_approval_requests"
    ADD CONSTRAINT "invoice_approval_requests_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoice_cancellations"
    ADD CONSTRAINT "invoice_cancellations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."invoice_cancellations"
    ADD CONSTRAINT "invoice_cancellations_original_invoice_id_fkey" FOREIGN KEY ("original_invoice_id") REFERENCES "public"."invoices"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_cancelled_by_fkey" FOREIGN KEY ("cancelled_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."kpi_scores"
    ADD CONSTRAINT "kpi_scores_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."lead_activities"
    ADD CONSTRAINT "lead_activities_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."lead_activities"
    ADD CONSTRAINT "lead_activities_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."leads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."lead_details"
    ADD CONSTRAINT "lead_details_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "public"."leads"("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."leads"
    ADD CONSTRAINT "leads_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."leave_requests"
    ADD CONSTRAINT "leave_requests_manager_id_fkey" FOREIGN KEY ("manager_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."payroll_deductions"
    ADD CONSTRAINT "payroll_deductions_payroll_record_id_fkey" FOREIGN KEY ("payroll_record_id") REFERENCES "public"."payroll_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payroll_earnings"
    ADD CONSTRAINT "payroll_earnings_payroll_record_id_fkey" FOREIGN KEY ("payroll_record_id") REFERENCES "public"."payroll_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payroll_records"
    ADD CONSTRAINT "payroll_records_processed_by_fkey" FOREIGN KEY ("processed_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."payroll_records"
    ADD CONSTRAINT "payroll_records_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quotation_markup_settings"
    ADD CONSTRAINT "quotation_markup_settings_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."quotations"
    ADD CONSTRAINT "quotations_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."salary_adjustments"
    ADD CONSTRAINT "salary_adjustments_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."salary_adjustments"
    ADD CONSTRAINT "salary_adjustments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."salary_adjustments"
    ADD CONSTRAINT "salary_adjustments_payroll_record_id_fkey" FOREIGN KEY ("payroll_record_id") REFERENCES "public"."payroll_records"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_monthly_targets"
    ADD CONSTRAINT "staff_monthly_targets_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "public"."staff_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."staff_profiles"
    ADD CONSTRAINT "staff_profiles_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."staff_profiles"
    ADD CONSTRAINT "staff_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_activity_log"
    ADD CONSTRAINT "task_activity_log_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."task_activity_log"
    ADD CONSTRAINT "task_activity_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."task_comments"
    ADD CONSTRAINT "task_comments_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."task_comments"
    ADD CONSTRAINT "task_comments_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."tasks"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "public"."user_profiles"("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."tour_package_fixed_pricing"
    ADD CONSTRAINT "tour_package_fixed_pricing_tour_package_id_fkey" FOREIGN KEY ("tour_package_id") REFERENCES "public"."tour_packages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "public"."branches"("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_manager_id_fkey" FOREIGN KEY ("manager_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendor_locations"
    ADD CONSTRAINT "vendor_locations_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "public"."vendors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendor_payments"
    ADD CONSTRAINT "vendor_payments_booking_vendor_item_id_fkey" FOREIGN KEY ("booking_vendor_item_id") REFERENCES "public"."booking_vendor_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vendor_payments"
    ADD CONSTRAINT "vendor_payments_vendor_id_fkey" FOREIGN KEY ("vendor_id") REFERENCES "public"."vendors"("id") ON DELETE CASCADE;



CREATE POLICY "Accounts can view bookings" ON "public"."bookings" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Accounts can view expenses" ON "public"."expenses" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Accounts can view invoice payments" ON "public"."invoice_payments" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Accounts can view invoices" ON "public"."invoices" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Accounts can view petty cash" ON "public"."expenses" FOR SELECT USING (("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role") AND ("expense_type" = 'petty_cash'::"text")));



CREATE POLICY "Accounts can view staff profiles" ON "public"."staff_profiles" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Accounts can view vendors" ON "public"."vendors" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role"));



CREATE POLICY "Admin can manage branches" ON "public"."branches" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admin can manage cancellations" ON "public"."invoice_cancellations" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Admins and HR can create shifts" ON "public"."attendance_shifts" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text"]))))));



CREATE POLICY "Admins and HR can delete shifts" ON "public"."attendance_shifts" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text"]))))));



CREATE POLICY "Admins and HR can manage payroll deductions" ON "public"."payroll_deductions" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text", 'manager'::"text"]))))));



CREATE POLICY "Admins and HR can manage payroll earnings" ON "public"."payroll_earnings" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text", 'manager'::"text"]))))));



CREATE POLICY "Admins and HR can update shifts" ON "public"."attendance_shifts" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text"]))))));



CREATE POLICY "Admins and HR can view all shifts" ON "public"."attendance_shifts" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'hrms'::"text"]))))));



CREATE POLICY "Admins and managers can delete bookings" ON "public"."bookings" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = ANY (ARRAY['admin'::"public"."app_role", 'manager'::"public"."app_role"]))))));



CREATE POLICY "Admins and managers can update any booking" ON "public"."bookings" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = ANY (ARRAY['admin'::"public"."app_role", 'manager'::"public"."app_role"]))))));



CREATE POLICY "Admins and managers can update submissions" ON "public"."attendance_submissions" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Admins can delete group tour dates" ON "public"."group_tour_dates" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can delete leads" ON "public"."leads" FOR DELETE USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Admins can delete profiles" ON "public"."user_profiles" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Admins can insert user profiles" ON "public"."user_profiles" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "Admins can manage agent profiles" ON "public"."agent_profiles" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can manage all roles" ON "public"."user_roles" TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can manage all targets" ON "public"."staff_monthly_targets" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text", 'hrms'::"text"]))))));



CREATE POLICY "Admins can manage geofences" ON "public"."office_geofences" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can manage permissions" ON "public"."module_permissions" TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can manage roles" ON "public"."user_roles" TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role")) WITH CHECK ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can update all attendance" ON "public"."attendance_records" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can update any profile" ON "public"."user_profiles" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Admins can update deletion requests" ON "public"."deletion_requests" FOR UPDATE USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role")) WITH CHECK ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can view all API logs" ON "public"."api_access_log" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Admins can view all agent profiles" ON "public"."agent_profiles" FOR SELECT USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Admins can view all attendance" ON "public"."attendance_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can view all audit logs" ON "public"."access_audit_log" FOR SELECT TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can view all branch audit logs" ON "public"."branch_audit_log" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can view all deletion requests" ON "public"."deletion_requests" FOR SELECT USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can view all device sessions" ON "public"."device_sessions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can view all notifications" ON "public"."notifications" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can view all profiles" ON "public"."user_profiles" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_roles"
  WHERE (("user_roles"."user_id" = "auth"."uid"()) AND ("user_roles"."role" = 'admin'::"public"."app_role")))));



CREATE POLICY "Admins can view all roles" ON "public"."user_roles" FOR SELECT TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins can view all submissions" ON "public"."attendance_submissions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Admins can view all user roles" ON "public"."user_roles" FOR SELECT TO "authenticated" USING ("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role"));



CREATE POLICY "Admins, managers, accounts can update approval requests" ON "public"."booking_approval_requests" FOR UPDATE USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Admins, managers, accounts can view all approval requests" ON "public"."booking_approval_requests" FOR SELECT USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Agents can update their assigned leads" ON "public"."leads" FOR UPDATE USING (("assigned_to" = "auth"."uid"())) WITH CHECK (("assigned_to" = "auth"."uid"()));



CREATE POLICY "Agents can view bookings they referred" ON "public"."bookings" FOR SELECT USING ((("referred_by_id" = "auth"."uid"()) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Agents can view their assigned leads" ON "public"."leads" FOR SELECT USING ((("assigned_to" = "auth"."uid"()) OR ("created_by" = "auth"."uid"()) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Agents can view their own commission records" ON "public"."commission_records" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."agent_profiles"
  WHERE (("agent_profiles"."user_id" = "auth"."uid"()) AND ("agent_profiles"."id" = "commission_records"."staff_id")))) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Agents can view their own profile" ON "public"."agent_profiles" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "All authenticated users can view markup settings" ON "public"."quotation_markup_settings" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Approvers can update invoice approval requests" ON "public"."invoice_approval_requests" FOR UPDATE TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Approvers can view all invoice approval requests" ON "public"."invoice_approval_requests" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Approvers can view all invoices" ON "public"."invoices" FOR SELECT TO "authenticated" USING (("public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'accounts'::"public"."app_role")));



CREATE POLICY "Authenticated users can create lead activities" ON "public"."lead_activities" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can insert company settings" ON "public"."company_settings" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can insert group tour dates" ON "public"."group_tour_dates" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can read employee sequences" ON "public"."employee_code_sequences" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can update company settings" ON "public"."company_settings" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can update group tour dates" ON "public"."group_tour_dates" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view company settings" ON "public"."company_settings" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view geofences" ON "public"."office_geofences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view invoice sequences" ON "public"."invoice_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view lead sequences" ON "public"."lead_id_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view non-GST invoice sequences" ON "public"."invoice_non_gst_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view permissions" ON "public"."module_permissions" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Authenticated users can view receipt sequences" ON "public"."receipt_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view role permissions" ON "public"."role_permissions" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view sequences" ON "public"."package_id_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view staff profiles" ON "public"."staff_profiles" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Authenticated users can view task sequences" ON "public"."task_id_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can approve/reject leave requests" ON "public"."leave_requests" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can create deletion requests" ON "public"."deletion_requests" FOR INSERT WITH CHECK ((("requester_id" = "auth"."uid"()) AND "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Managers can create staff profiles" ON "public"."staff_profiles" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Managers can delete staff profiles" ON "public"."staff_profiles" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can delete tasks" ON "public"."tasks" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can insert attendance records" ON "public"."attendance_records" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can manage commission records" ON "public"."commission_records" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can manage incentive records" ON "public"."incentive_records" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can manage payroll records" ON "public"."payroll_records" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can manage salary adjustments" ON "public"."salary_adjustments" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can manage salary structures" ON "public"."salary_structures" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can update all tasks" ON "public"."tasks" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can update attendance records" ON "public"."attendance_records" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can update branch attendance" ON "public"."attendance_records" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."user_id" = "auth"."uid"()) AND ("up"."role" = 'manager'::"text") AND ("up"."branch_id" = "attendance_records"."branch_id")))));



CREATE POLICY "Managers can update staff profiles" ON "public"."staff_profiles" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can view all KPI scores" ON "public"."kpi_scores" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can view all attendance records" ON "public"."attendance_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can view all leave requests" ON "public"."leave_requests" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can view all tasks" ON "public"."tasks" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "Managers can view branch attendance" ON "public"."attendance_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."user_id" = "auth"."uid"()) AND ("up"."role" = 'manager'::"text") AND ("up"."branch_id" = "attendance_records"."branch_id")))));



CREATE POLICY "Managers can view branch submissions" ON "public"."attendance_submissions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles" "up"
  WHERE (("up"."user_id" = "auth"."uid"()) AND ("up"."role" = 'manager'::"text") AND ("up"."branch_id" = "up"."branch_id")))));



CREATE POLICY "Managers can view profiles from their branch" ON "public"."user_profiles" FOR SELECT USING (("public"."is_manager"("auth"."uid"()) AND ("public"."get_user_branch_id"("auth"."uid"()) = "branch_id") AND ("branch_id" IS NOT NULL)));



CREATE POLICY "Managers can view sync logs" ON "public"."yellow_app_sync_log" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Managers can view their own deletion requests" ON "public"."deletion_requests" FOR SELECT USING ((("requester_id" = "auth"."uid"()) AND "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Only admins can insert markup settings" ON "public"."quotation_markup_settings" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Only admins can update markup settings" ON "public"."quotation_markup_settings" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = 'admin'::"text")))));



CREATE POLICY "Service role can manage profiles" ON "public"."user_profiles" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Service role can manage user roles" ON "public"."user_roles" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Service role can view all profiles" ON "public"."user_profiles" FOR SELECT USING ((((("current_setting"('request.jwt.claims'::"text", true))::json ->> 'role'::"text") = 'service_role'::"text") OR ("auth"."uid"() IS NULL)));



CREATE POLICY "Service role can view all roles" ON "public"."user_roles" FOR SELECT USING ((((("current_setting"('request.jwt.claims'::"text", true))::json ->> 'role'::"text") = 'service_role'::"text") OR ("auth"."uid"() IS NULL)));



CREATE POLICY "Staff can create approval requests" ON "public"."booking_approval_requests" FOR INSERT WITH CHECK (("requested_by" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))));



CREATE POLICY "Staff can create invoice approval requests" ON "public"."invoice_approval_requests" FOR INSERT TO "authenticated" WITH CHECK (("requested_by" IN ( SELECT "user_profiles"."user_id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))));



CREATE POLICY "Staff can create leads" ON "public"."leads" FOR INSERT WITH CHECK (("auth"."uid"() = "created_by"));



CREATE POLICY "Staff can insert own attendance" ON "public"."attendance_records" FOR INSERT WITH CHECK (("employee_id" = "auth"."uid"()));



CREATE POLICY "Staff can insert own submissions" ON "public"."attendance_submissions" FOR INSERT WITH CHECK (("employee_id" = "auth"."uid"()));



CREATE POLICY "Staff can update their own or assigned leads" ON "public"."leads" FOR UPDATE USING ((("auth"."uid"() = "created_by") OR ("auth"."uid"() = "assigned_to") OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Staff can view own attendance" ON "public"."attendance_records" FOR SELECT USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Staff can view own invoices including pending" ON "public"."invoices" FOR SELECT TO "authenticated" USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Staff can view own submissions" ON "public"."attendance_submissions" FOR SELECT USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Staff can view their assigned notifications" ON "public"."app_notifications" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."app_notification_recipients"
  WHERE (("app_notification_recipients"."notification_id" = "app_notifications"."id") AND ("app_notification_recipients"."user_id" = "auth"."uid"())))));



CREATE POLICY "Staff can view their own approval requests" ON "public"."booking_approval_requests" FOR SELECT USING (("requested_by" = "auth"."uid"()));



CREATE POLICY "Staff can view their own commission records" ON "public"."commission_records" FOR SELECT USING ((("staff_id" IN ( SELECT "staff_profiles"."id"
   FROM "public"."staff_profiles"
  WHERE ("staff_profiles"."user_id" = "auth"."uid"()))) OR ("auth"."uid"() IS NOT NULL)));



CREATE POLICY "Staff can view their own incentive records" ON "public"."incentive_records" FOR SELECT USING ((("staff_id" IN ( SELECT "staff_profiles"."id"
   FROM "public"."staff_profiles"
  WHERE ("staff_profiles"."user_id" = "auth"."uid"()))) OR ("auth"."uid"() IS NOT NULL)));



CREATE POLICY "Staff can view their own invoice approval requests" ON "public"."invoice_approval_requests" FOR SELECT TO "authenticated" USING (("requested_by" = "auth"."uid"()));



CREATE POLICY "Staff can view their own or assigned leads" ON "public"."leads" FOR SELECT USING ((("auth"."uid"() = "created_by") OR ("auth"."uid"() = "assigned_to") OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Staff can view their own payroll deductions" ON "public"."payroll_deductions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."payroll_records" "pr"
     JOIN "public"."staff_profiles" "sp" ON (("pr"."staff_id" = "sp"."id")))
  WHERE (("pr"."id" = "payroll_deductions"."payroll_record_id") AND ("sp"."user_id" = "auth"."uid"())))));



CREATE POLICY "Staff can view their own payroll earnings" ON "public"."payroll_earnings" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."payroll_records" "pr"
     JOIN "public"."staff_profiles" "sp" ON (("pr"."staff_id" = "sp"."id")))
  WHERE (("pr"."id" = "payroll_earnings"."payroll_record_id") AND ("sp"."user_id" = "auth"."uid"())))));



CREATE POLICY "Staff can view their own payroll records" ON "public"."payroll_records" FOR SELECT USING ((("staff_id" IN ( SELECT "staff_profiles"."id"
   FROM "public"."staff_profiles"
  WHERE ("staff_profiles"."user_id" = "auth"."uid"()))) OR ("auth"."uid"() IS NOT NULL)));



CREATE POLICY "Staff can view their own targets" ON "public"."staff_monthly_targets" FOR SELECT USING ((("staff_id" IN ( SELECT "staff_profiles"."id"
   FROM "public"."staff_profiles"
  WHERE ("staff_profiles"."user_id" = "auth"."uid"()))) OR (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text", 'hrms'::"text"])))))));



CREATE POLICY "System can create notifications" ON "public"."notifications" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "System can create task activity logs" ON "public"."task_activity_log" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "System can insert audit logs" ON "public"."access_audit_log" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "System can insert audit logs" ON "public"."group_tour_capacity_audit" FOR INSERT WITH CHECK (true);



CREATE POLICY "System can insert branch audit logs" ON "public"."branch_audit_log" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "System can insert profiles" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "System can manage KPI scores" ON "public"."kpi_scores" USING ((EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))));



CREATE POLICY "System can manage receipt sequences" ON "public"."receipt_sequences" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "System can manage sync logs" ON "public"."yellow_app_sync_log" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create DMC vendor packages" ON "public"."dmc_vendor_packages" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create booking vendor items" ON "public"."booking_vendor_items" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create car rate lists" ON "public"."car_rate_lists" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create car rate rows" ON "public"."car_rate_rows" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create car rate seasons" ON "public"."car_rate_seasons" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create commission records" ON "public"."commission_records" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create expense_bookings" ON "public"."expense_bookings" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create expenses" ON "public"."expenses" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create fixed pricing" ON "public"."tour_package_fixed_pricing" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create incentive records" ON "public"."incentive_records" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create invoice payments" ON "public"."invoice_payments" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "recorded_by")));



CREATE POLICY "Users can create invoices" ON "public"."invoices" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create lead details" ON "public"."lead_details" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create petty cash ledger entries" ON "public"."petty_cash_ledger" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create quotations" ON "public"."quotations" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create rate lists" ON "public"."hotel_rate_lists" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create rate rows" ON "public"."hotel_rate_rows" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create rate seasons" ON "public"."hotel_rate_seasons" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create salary adjustments" ON "public"."salary_adjustments" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create task comments for accessible tasks" ON "public"."task_comments" FOR INSERT WITH CHECK ((("author_id" = "auth"."uid"()) AND ((EXISTS ( SELECT 1
   FROM "public"."tasks"
  WHERE (("tasks"."id" = "task_comments"."task_id") AND (("tasks"."assigned_to" = "auth"."uid"()) OR ("tasks"."assigned_by" = "auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))))));



CREATE POLICY "Users can create tasks" ON "public"."tasks" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (("assigned_by" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))) OR (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."user_id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"]))))))));



CREATE POLICY "Users can create their own agent profile" ON "public"."agent_profiles" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can create their own bookings" ON "public"."bookings" FOR INSERT WITH CHECK (("auth"."uid"() = "created_by"));



CREATE POLICY "Users can create their own leave requests" ON "public"."leave_requests" FOR INSERT WITH CHECK (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can create tour packages" ON "public"."tour_packages" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create vendor locations" ON "public"."vendor_locations" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can create vendor payments" ON "public"."vendor_payments" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can create vendors" ON "public"."vendors" FOR INSERT WITH CHECK ((("auth"."uid"() IS NOT NULL) AND ("auth"."uid"() = "created_by")));



CREATE POLICY "Users can delete DMC vendor packages" ON "public"."dmc_vendor_packages" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete booking vendor items" ON "public"."booking_vendor_items" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete car rate lists" ON "public"."car_rate_lists" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete car rate rows" ON "public"."car_rate_rows" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete car rate seasons" ON "public"."car_rate_seasons" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete expense_bookings" ON "public"."expense_bookings" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete expenses" ON "public"."expenses" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete fixed pricing" ON "public"."tour_package_fixed_pricing" FOR DELETE TO "authenticated" USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete invoice payments" ON "public"."invoice_payments" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete invoices" ON "public"."invoices" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete lead details" ON "public"."lead_details" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete petty cash ledger entries" ON "public"."petty_cash_ledger" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete quotations" ON "public"."quotations" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete rate lists" ON "public"."hotel_rate_lists" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete rate rows" ON "public"."hotel_rate_rows" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete rate seasons" ON "public"."hotel_rate_seasons" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete their lead activities" ON "public"."lead_activities" FOR DELETE USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Users can delete tour packages" ON "public"."tour_packages" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete vendor locations" ON "public"."vendor_locations" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete vendor payments" ON "public"."vendor_payments" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can delete vendors" ON "public"."vendors" FOR DELETE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can insert fixed pricing" ON "public"."tour_package_fixed_pricing" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can insert their own attendance records" ON "public"."attendance_records" FOR INSERT WITH CHECK (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can manage their own device sessions" ON "public"."device_sessions" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update DMC vendor packages" ON "public"."dmc_vendor_packages" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update booking vendor items" ON "public"."booking_vendor_items" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update car rate lists" ON "public"."car_rate_lists" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update car rate rows" ON "public"."car_rate_rows" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update car rate seasons" ON "public"."car_rate_seasons" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update expense_bookings" ON "public"."expense_bookings" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update expenses" ON "public"."expenses" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update fixed pricing" ON "public"."tour_package_fixed_pricing" FOR UPDATE TO "authenticated" USING (("auth"."uid"() IS NOT NULL)) WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update invoice payments" ON "public"."invoice_payments" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update invoices" ON "public"."invoices" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update lead details" ON "public"."lead_details" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update petty cash ledger entries" ON "public"."petty_cash_ledger" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update quotations" ON "public"."quotations" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update rate lists" ON "public"."hotel_rate_lists" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update rate rows" ON "public"."hotel_rate_rows" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update rate seasons" ON "public"."hotel_rate_seasons" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update tasks assigned to them" ON "public"."tasks" FOR UPDATE USING ((("assigned_to" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Users can update their lead activities" ON "public"."lead_activities" FOR UPDATE USING (("created_by" = "auth"."uid"()));



CREATE POLICY "Users can update their own attendance records" ON "public"."attendance_records" FOR UPDATE USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can update their own bookings" ON "public"."bookings" FOR UPDATE USING (("created_by" = "auth"."uid"())) WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "Users can update their own notifications" ON "public"."notifications" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can update their own pending leave requests" ON "public"."leave_requests" FOR UPDATE USING ((("employee_id" = "auth"."uid"()) AND ("status" = 'pending'::"text")));



CREATE POLICY "Users can update their own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update tour packages" ON "public"."tour_packages" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update vendor locations" ON "public"."vendor_locations" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update vendor payments" ON "public"."vendor_payments" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can update vendors" ON "public"."vendors" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view accessible bookings" ON "public"."bookings" FOR SELECT USING ((("auth"."uid"() = "created_by") OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Users can view accessible invoices" ON "public"."invoices" FOR SELECT USING ((("auth"."uid"() = "created_by") OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Users can view accessible tasks" ON "public"."tasks" FOR SELECT USING ((("assigned_to" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))) OR ("assigned_by" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))) OR "public"."has_role"("auth"."uid"(), 'admin'::"public"."app_role") OR "public"."has_role"("auth"."uid"(), 'manager'::"public"."app_role")));



CREATE POLICY "Users can view all DMC vendor packages" ON "public"."dmc_vendor_packages" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all booking vendor items" ON "public"."booking_vendor_items" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all car rate lists" ON "public"."car_rate_lists" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all car rate rows" ON "public"."car_rate_rows" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all car rate seasons" ON "public"."car_rate_seasons" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all fixed pricing" ON "public"."tour_package_fixed_pricing" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all lead details" ON "public"."lead_details" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all petty cash ledger entries" ON "public"."petty_cash_ledger" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all quotations" ON "public"."quotations" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all rate lists" ON "public"."hotel_rate_lists" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all rate rows" ON "public"."hotel_rate_rows" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all rate seasons" ON "public"."hotel_rate_seasons" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all tour packages" ON "public"."tour_packages" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all vendor locations" ON "public"."vendor_locations" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all vendor payments" ON "public"."vendor_payments" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view all vendors" ON "public"."vendors" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view audit logs" ON "public"."group_tour_capacity_audit" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view booking sequences" ON "public"."booking_id_sequences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view branches" ON "public"."branches" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view cancellations" ON "public"."invoice_cancellations" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view expense_bookings" ON "public"."expense_bookings" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view expenses" ON "public"."expenses" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view fixed pricing" ON "public"."tour_package_fixed_pricing" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "Users can view group tour dates" ON "public"."group_tour_dates" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view invoice payments" ON "public"."invoice_payments" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view lead activities" ON "public"."lead_activities" FOR SELECT USING (true);



CREATE POLICY "Users can view salary adjustments" ON "public"."salary_adjustments" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view salary structures" ON "public"."salary_structures" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "Users can view task activity for accessible tasks" ON "public"."task_activity_log" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."tasks"
  WHERE (("tasks"."id" = "task_activity_log"."task_id") AND (("tasks"."assigned_to" = "auth"."uid"()) OR ("tasks"."assigned_by" = "auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"])))))));



CREATE POLICY "Users can view task comments for accessible tasks" ON "public"."task_comments" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."tasks"
  WHERE (("tasks"."id" = "task_comments"."task_id") AND (("tasks"."assigned_to" = "auth"."uid"()) OR ("tasks"."assigned_by" = "auth"."uid"()))))) OR (EXISTS ( SELECT 1
   FROM "public"."user_profiles"
  WHERE (("user_profiles"."id" = "auth"."uid"()) AND ("user_profiles"."role" = ANY (ARRAY['admin'::"text", 'manager'::"text"])))))));



CREATE POLICY "Users can view tasks assigned to them" ON "public"."tasks" FOR SELECT USING (("assigned_to" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view tasks they created" ON "public"."tasks" FOR SELECT USING (("assigned_by" IN ( SELECT "user_profiles"."id"
   FROM "public"."user_profiles"
  WHERE ("user_profiles"."user_id" = "auth"."uid"()))));



CREATE POLICY "Users can view their own KPI scores" ON "public"."kpi_scores" FOR SELECT USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own attendance records" ON "public"."attendance_records" FOR SELECT USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own audit logs" ON "public"."access_audit_log" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own device sessions" ON "public"."device_sessions" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own leave requests" ON "public"."leave_requests" FOR SELECT USING (("employee_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own notifications" ON "public"."notifications" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own profile" ON "public"."user_profiles" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own roles" ON "public"."user_roles" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can view their own shift" ON "public"."attendance_shifts" FOR SELECT USING (("user_id" = "auth"."uid"()));



ALTER TABLE "public"."access_audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."agent_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."api_access_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_shifts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."attendance_submissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_approval_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_id_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."booking_vendor_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branch_audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."branches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."car_rate_lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."car_rate_rows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."car_rate_seasons" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commission_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."company_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."deletion_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."device_sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dmc_vendor_packages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."employee_code_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expense_bookings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."expenses" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_tour_capacity_audit" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."group_tour_dates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hotel_rate_lists" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hotel_rate_rows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."hotel_rate_seasons" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."incentive_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_approval_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_cancellations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_non_gst_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoice_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."kpi_scores" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lead_activities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."lead_id_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."leave_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."module_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."office_geofences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."package_id_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payroll_deductions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payroll_earnings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payroll_records" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."petty_cash_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quotation_markup_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quotations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."receipt_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."role_permissions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."salary_adjustments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."salary_structures" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."staff_monthly_targets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."staff_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."task_activity_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."task_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."task_id_sequences" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tasks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tour_package_fixed_pricing" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tour_packages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_roles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vendor_locations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vendor_payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vendors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."yellow_app_sync_log" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."agent_profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."booking_approval_requests";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."bookings";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."commission_records";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."hotel_rate_lists";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."hotel_rate_rows";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."hotel_rate_seasons";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."invoices";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."lead_activities";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."leads";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."quotations";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."tour_packages";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."user_profiles";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."vendors";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";














































































































































































GRANT ALL ON FUNCTION "public"."app_handle_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."app_handle_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_handle_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_booking_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."assign_booking_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_booking_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."assign_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_lead_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."assign_lead_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_lead_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_package_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."assign_package_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_package_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."assign_task_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."assign_task_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."assign_task_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_create_commission_record"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_create_commission_record"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_create_commission_record"() TO "service_role";



GRANT ALL ON FUNCTION "public"."backfill_branch_data"() TO "anon";
GRANT ALL ON FUNCTION "public"."backfill_branch_data"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."backfill_branch_data"() TO "service_role";



GRANT ALL ON FUNCTION "public"."branch_migration_report"() TO "anon";
GRANT ALL ON FUNCTION "public"."branch_migration_report"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."branch_migration_report"() TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_booking_commission"("booking_id" "uuid", "staff_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_booking_commission"("booking_id" "uuid", "staff_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_booking_commission"("booking_id" "uuid", "staff_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_all_users_consistency"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_all_users_consistency"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_all_users_consistency"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_submission_limit"("p_employee_id" "uuid", "p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."check_submission_limit"("p_employee_id" "uuid", "p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_submission_limit"("p_employee_id" "uuid", "p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_orphaned_profiles"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_profiles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_orphaned_profiles"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_user_by_email"("user_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_user_by_email"("user_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_user_by_email"("user_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_attendance_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."compute_attendance_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_attendance_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."compute_kpi_scores"("emp_id" "uuid", "start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."compute_kpi_scores"("emp_id" "uuid", "start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."compute_kpi_scores"("emp_id" "uuid", "start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_agent_commission_on_booking"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_agent_commission_on_booking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_agent_commission_on_booking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_agent_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_agent_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_agent_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_group_tour_capacity"("p_package_id" "uuid", "p_travel_date" "date", "p_booking_id" "uuid", "p_pax_count" integer, "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_group_tour_capacity"("p_package_id" "uuid", "p_travel_date" "date", "p_booking_id" "uuid", "p_pax_count" integer, "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_group_tour_capacity"("p_package_id" "uuid", "p_travel_date" "date", "p_booking_id" "uuid", "p_pax_count" integer, "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_booking_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_booking_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_booking_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_cancellation_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_cancellation_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_cancellation_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_employee_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_employee_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_employee_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_gst_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_gst_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_gst_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_lead_id"("customer_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_lead_id"("customer_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_lead_id"("customer_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_non_gst_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_non_gst_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_non_gst_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_package_id"("pkg_category" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."generate_package_id"("pkg_category" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_package_id"("pkg_category" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_receipt_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_receipt_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_receipt_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_task_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_daily_submission_count"("p_employee_id" "uuid", "p_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_daily_submission_count"("p_employee_id" "uuid", "p_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_daily_submission_count"("p_employee_id" "uuid", "p_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_branch_id"("_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_branch_id"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_branch_id"("_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_branch_ids"("_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_branch_ids"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_branch_ids"("_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_agent_role_assignment"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_agent_role_assignment"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_agent_role_assignment"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") TO "anon";
GRANT ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."has_role"("_user_id" "uuid", "_role" "public"."app_role") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_inside_geofence"("lat" numeric, "lng" numeric, "geofence_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_inside_geofence"("lat" numeric, "lng" numeric, "geofence_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_inside_geofence"("lat" numeric, "lng" numeric, "geofence_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_manager"("_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_manager"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_manager"("_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_task_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_task_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_task_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_admins"("notification_type" "text", "notification_title" "text", "notification_message" "text", "notification_data" "jsonb", "reference_id" "uuid", "created_by_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."notify_admins"("notification_type" "text", "notification_title" "text", "notification_message" "text", "notification_data" "jsonb", "reference_id" "uuid", "created_by_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_admins"("notification_type" "text", "notification_title" "text", "notification_message" "text", "notification_data" "jsonb", "reference_id" "uuid", "created_by_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_booking"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_booking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_booking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_followup"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_followup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_followup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_lead"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_lead"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_lead"() TO "service_role";



GRANT ALL ON FUNCTION "public"."parse_human_date"("date_str" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."parse_human_date"("date_str" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."parse_human_date"("date_str" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_checkin"("lat" numeric, "lng" numeric, "device_id" "text", "geofence_id" "uuid", "photo_url" "text", "accuracy_meters" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."rpc_checkin"("lat" numeric, "lng" numeric, "device_id" "text", "geofence_id" "uuid", "photo_url" "text", "accuracy_meters" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."rpc_checkin"("lat" numeric, "lng" numeric, "device_id" "text", "geofence_id" "uuid", "photo_url" "text", "accuracy_meters" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_checkout"("lat" numeric, "lng" numeric, "device_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."rpc_checkout"("lat" numeric, "lng" numeric, "device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rpc_checkout"("lat" numeric, "lng" numeric, "device_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rpc_get_attendance_summary"("emp_id" "uuid", "period_start" "date", "period_end" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."rpc_get_attendance_summary"("emp_id" "uuid", "period_start" "date", "period_end" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rpc_get_attendance_summary"("emp_id" "uuid", "period_start" "date", "period_end" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_booking_branch_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_booking_branch_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_booking_branch_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_cancellation_invoice_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_cancellation_invoice_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_cancellation_invoice_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_expense_branch_id"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_expense_branch_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_expense_branch_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_user_roles"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_user_roles"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_user_roles"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_agent_stats"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_agent_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_agent_stats"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_assigned_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_assigned_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_assigned_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_attendance_submission_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_attendance_submission_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_attendance_submission_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_commission_on_tour_completion"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_commission_on_tour_completion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_commission_on_tour_completion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_invoice_approval_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_invoice_approval_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_invoice_approval_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_overdue_tasks"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_overdue_tasks"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_overdue_tasks"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_staff_monthly_target"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_staff_monthly_target"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_staff_monthly_target"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_staff_monthly_targets_on_booking"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_staff_monthly_targets_on_booking"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_staff_monthly_targets_on_booking"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."user_has_branch_access"("_user_id" "uuid", "_branch_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."user_has_branch_access"("_user_id" "uuid", "_branch_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."user_has_branch_access"("_user_id" "uuid", "_branch_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_user_consistency"("user_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."validate_user_consistency"("user_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_user_consistency"("user_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."validate_user_profile_auth"() TO "anon";
GRANT ALL ON FUNCTION "public"."validate_user_profile_auth"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."validate_user_profile_auth"() TO "service_role";
























GRANT ALL ON TABLE "public"."access_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."access_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."access_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."agent_profiles" TO "anon";
GRANT ALL ON TABLE "public"."agent_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."agent_leaderboard" TO "anon";
GRANT ALL ON TABLE "public"."agent_leaderboard" TO "authenticated";
GRANT ALL ON TABLE "public"."agent_leaderboard" TO "service_role";



GRANT ALL ON TABLE "public"."api_access_log" TO "anon";
GRANT ALL ON TABLE "public"."api_access_log" TO "authenticated";
GRANT ALL ON TABLE "public"."api_access_log" TO "service_role";



GRANT ALL ON TABLE "public"."app_notification_recipients" TO "anon";
GRANT ALL ON TABLE "public"."app_notification_recipients" TO "authenticated";
GRANT ALL ON TABLE "public"."app_notification_recipients" TO "service_role";



GRANT ALL ON TABLE "public"."app_notification_recipients_backup" TO "anon";
GRANT ALL ON TABLE "public"."app_notification_recipients_backup" TO "authenticated";
GRANT ALL ON TABLE "public"."app_notification_recipients_backup" TO "service_role";



GRANT ALL ON TABLE "public"."app_notifications" TO "anon";
GRANT ALL ON TABLE "public"."app_notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."app_notifications" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_records" TO "anon";
GRANT ALL ON TABLE "public"."attendance_records" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_records" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_shifts" TO "anon";
GRANT ALL ON TABLE "public"."attendance_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_shifts" TO "service_role";



GRANT ALL ON TABLE "public"."attendance_submissions" TO "anon";
GRANT ALL ON TABLE "public"."attendance_submissions" TO "authenticated";
GRANT ALL ON TABLE "public"."attendance_submissions" TO "service_role";



GRANT ALL ON TABLE "public"."booking_approval_requests" TO "anon";
GRANT ALL ON TABLE "public"."booking_approval_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_approval_requests" TO "service_role";



GRANT ALL ON TABLE "public"."booking_id_sequences" TO "anon";
GRANT ALL ON TABLE "public"."booking_id_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_id_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."booking_vendor_items" TO "anon";
GRANT ALL ON TABLE "public"."booking_vendor_items" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_vendor_items" TO "service_role";



GRANT ALL ON TABLE "public"."bookings" TO "anon";
GRANT ALL ON TABLE "public"."bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."bookings" TO "service_role";



GRANT ALL ON TABLE "public"."branch_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."branch_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."branches" TO "anon";
GRANT ALL ON TABLE "public"."branches" TO "authenticated";
GRANT ALL ON TABLE "public"."branches" TO "service_role";



GRANT ALL ON TABLE "public"."office_geofences" TO "anon";
GRANT ALL ON TABLE "public"."office_geofences" TO "authenticated";
GRANT ALL ON TABLE "public"."office_geofences" TO "service_role";



GRANT ALL ON TABLE "public"."branch_geofence_view" TO "anon";
GRANT ALL ON TABLE "public"."branch_geofence_view" TO "authenticated";
GRANT ALL ON TABLE "public"."branch_geofence_view" TO "service_role";



GRANT ALL ON TABLE "public"."cancellation_invoice_sequences" TO "anon";
GRANT ALL ON TABLE "public"."cancellation_invoice_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."cancellation_invoice_sequences" TO "service_role";



GRANT ALL ON SEQUENCE "public"."cancellation_invoice_sequences_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."cancellation_invoice_sequences_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."cancellation_invoice_sequences_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."car_rate_lists" TO "anon";
GRANT ALL ON TABLE "public"."car_rate_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."car_rate_lists" TO "service_role";



GRANT ALL ON TABLE "public"."car_rate_rows" TO "anon";
GRANT ALL ON TABLE "public"."car_rate_rows" TO "authenticated";
GRANT ALL ON TABLE "public"."car_rate_rows" TO "service_role";



GRANT ALL ON TABLE "public"."car_rate_seasons" TO "anon";
GRANT ALL ON TABLE "public"."car_rate_seasons" TO "authenticated";
GRANT ALL ON TABLE "public"."car_rate_seasons" TO "service_role";



GRANT ALL ON TABLE "public"."commission_records" TO "anon";
GRANT ALL ON TABLE "public"."commission_records" TO "authenticated";
GRANT ALL ON TABLE "public"."commission_records" TO "service_role";



GRANT ALL ON TABLE "public"."company_settings" TO "anon";
GRANT ALL ON TABLE "public"."company_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."company_settings" TO "service_role";



GRANT ALL ON TABLE "public"."deletion_requests" TO "anon";
GRANT ALL ON TABLE "public"."deletion_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."deletion_requests" TO "service_role";



GRANT ALL ON TABLE "public"."device_sessions" TO "anon";
GRANT ALL ON TABLE "public"."device_sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."device_sessions" TO "service_role";



GRANT ALL ON TABLE "public"."dmc_vendor_packages" TO "anon";
GRANT ALL ON TABLE "public"."dmc_vendor_packages" TO "authenticated";
GRANT ALL ON TABLE "public"."dmc_vendor_packages" TO "service_role";



GRANT ALL ON TABLE "public"."employee_code_sequences" TO "anon";
GRANT ALL ON TABLE "public"."employee_code_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."employee_code_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."expense_bookings" TO "anon";
GRANT ALL ON TABLE "public"."expense_bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."expense_bookings" TO "service_role";



GRANT ALL ON TABLE "public"."expenses" TO "anon";
GRANT ALL ON TABLE "public"."expenses" TO "authenticated";
GRANT ALL ON TABLE "public"."expenses" TO "service_role";



GRANT ALL ON TABLE "public"."group_tour_capacity_audit" TO "anon";
GRANT ALL ON TABLE "public"."group_tour_capacity_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."group_tour_capacity_audit" TO "service_role";



GRANT ALL ON TABLE "public"."group_tour_dates" TO "anon";
GRANT ALL ON TABLE "public"."group_tour_dates" TO "authenticated";
GRANT ALL ON TABLE "public"."group_tour_dates" TO "service_role";



GRANT ALL ON TABLE "public"."hotel_rate_lists" TO "anon";
GRANT ALL ON TABLE "public"."hotel_rate_lists" TO "authenticated";
GRANT ALL ON TABLE "public"."hotel_rate_lists" TO "service_role";



GRANT ALL ON TABLE "public"."hotel_rate_rows" TO "anon";
GRANT ALL ON TABLE "public"."hotel_rate_rows" TO "authenticated";
GRANT ALL ON TABLE "public"."hotel_rate_rows" TO "service_role";



GRANT ALL ON TABLE "public"."hotel_rate_seasons" TO "anon";
GRANT ALL ON TABLE "public"."hotel_rate_seasons" TO "authenticated";
GRANT ALL ON TABLE "public"."hotel_rate_seasons" TO "service_role";



GRANT ALL ON TABLE "public"."incentive_records" TO "anon";
GRANT ALL ON TABLE "public"."incentive_records" TO "authenticated";
GRANT ALL ON TABLE "public"."incentive_records" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_approval_requests" TO "anon";
GRANT ALL ON TABLE "public"."invoice_approval_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_approval_requests" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_cancellations" TO "anon";
GRANT ALL ON TABLE "public"."invoice_cancellations" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_cancellations" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_non_gst_sequences" TO "anon";
GRANT ALL ON TABLE "public"."invoice_non_gst_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_non_gst_sequences" TO "service_role";



GRANT ALL ON SEQUENCE "public"."invoice_non_gst_sequences_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."invoice_non_gst_sequences_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."invoice_non_gst_sequences_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_payments" TO "anon";
GRANT ALL ON TABLE "public"."invoice_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_payments" TO "service_role";



GRANT ALL ON TABLE "public"."invoice_sequences" TO "anon";
GRANT ALL ON TABLE "public"."invoice_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."invoice_sequences" TO "service_role";



GRANT ALL ON SEQUENCE "public"."invoice_sequences_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."invoice_sequences_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."invoice_sequences_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT ALL ON TABLE "public"."kpi_scores" TO "anon";
GRANT ALL ON TABLE "public"."kpi_scores" TO "authenticated";
GRANT ALL ON TABLE "public"."kpi_scores" TO "service_role";



GRANT ALL ON TABLE "public"."lead_activities" TO "anon";
GRANT ALL ON TABLE "public"."lead_activities" TO "authenticated";
GRANT ALL ON TABLE "public"."lead_activities" TO "service_role";



GRANT ALL ON TABLE "public"."lead_details" TO "anon";
GRANT ALL ON TABLE "public"."lead_details" TO "authenticated";
GRANT ALL ON TABLE "public"."lead_details" TO "service_role";



GRANT ALL ON TABLE "public"."lead_id_sequences" TO "anon";
GRANT ALL ON TABLE "public"."lead_id_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."lead_id_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."leads" TO "anon";
GRANT ALL ON TABLE "public"."leads" TO "authenticated";
GRANT ALL ON TABLE "public"."leads" TO "service_role";



GRANT ALL ON TABLE "public"."leave_requests" TO "anon";
GRANT ALL ON TABLE "public"."leave_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."leave_requests" TO "service_role";



GRANT ALL ON TABLE "public"."module_permissions" TO "anon";
GRANT ALL ON TABLE "public"."module_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."module_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."package_id_sequences" TO "anon";
GRANT ALL ON TABLE "public"."package_id_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."package_id_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."payroll_deductions" TO "anon";
GRANT ALL ON TABLE "public"."payroll_deductions" TO "authenticated";
GRANT ALL ON TABLE "public"."payroll_deductions" TO "service_role";



GRANT ALL ON TABLE "public"."payroll_earnings" TO "anon";
GRANT ALL ON TABLE "public"."payroll_earnings" TO "authenticated";
GRANT ALL ON TABLE "public"."payroll_earnings" TO "service_role";



GRANT ALL ON TABLE "public"."payroll_records" TO "anon";
GRANT ALL ON TABLE "public"."payroll_records" TO "authenticated";
GRANT ALL ON TABLE "public"."payroll_records" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."pending_attendance_with_details" TO "anon";
GRANT ALL ON TABLE "public"."pending_attendance_with_details" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_attendance_with_details" TO "service_role";



GRANT ALL ON TABLE "public"."petty_cash_ledger" TO "anon";
GRANT ALL ON TABLE "public"."petty_cash_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."petty_cash_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."quotation_markup_settings" TO "anon";
GRANT ALL ON TABLE "public"."quotation_markup_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."quotation_markup_settings" TO "service_role";



GRANT ALL ON TABLE "public"."quotations" TO "anon";
GRANT ALL ON TABLE "public"."quotations" TO "authenticated";
GRANT ALL ON TABLE "public"."quotations" TO "service_role";



GRANT ALL ON TABLE "public"."receipt_sequences" TO "anon";
GRANT ALL ON TABLE "public"."receipt_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."receipt_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."role_permissions" TO "anon";
GRANT ALL ON TABLE "public"."role_permissions" TO "authenticated";
GRANT ALL ON TABLE "public"."role_permissions" TO "service_role";



GRANT ALL ON TABLE "public"."salary_adjustments" TO "anon";
GRANT ALL ON TABLE "public"."salary_adjustments" TO "authenticated";
GRANT ALL ON TABLE "public"."salary_adjustments" TO "service_role";



GRANT ALL ON TABLE "public"."salary_structures" TO "anon";
GRANT ALL ON TABLE "public"."salary_structures" TO "authenticated";
GRANT ALL ON TABLE "public"."salary_structures" TO "service_role";



GRANT ALL ON TABLE "public"."staff_monthly_targets" TO "anon";
GRANT ALL ON TABLE "public"."staff_monthly_targets" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_monthly_targets" TO "service_role";



GRANT ALL ON TABLE "public"."staff_profiles" TO "anon";
GRANT ALL ON TABLE "public"."staff_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."staff_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."task_activity_log" TO "anon";
GRANT ALL ON TABLE "public"."task_activity_log" TO "authenticated";
GRANT ALL ON TABLE "public"."task_activity_log" TO "service_role";



GRANT ALL ON TABLE "public"."task_comments" TO "anon";
GRANT ALL ON TABLE "public"."task_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."task_comments" TO "service_role";



GRANT ALL ON TABLE "public"."task_id_sequences" TO "anon";
GRANT ALL ON TABLE "public"."task_id_sequences" TO "authenticated";
GRANT ALL ON TABLE "public"."task_id_sequences" TO "service_role";



GRANT ALL ON TABLE "public"."tasks" TO "anon";
GRANT ALL ON TABLE "public"."tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."tasks" TO "service_role";



GRANT ALL ON TABLE "public"."tour_package_fixed_pricing" TO "anon";
GRANT ALL ON TABLE "public"."tour_package_fixed_pricing" TO "authenticated";
GRANT ALL ON TABLE "public"."tour_package_fixed_pricing" TO "service_role";



GRANT ALL ON TABLE "public"."tour_packages" TO "anon";
GRANT ALL ON TABLE "public"."tour_packages" TO "authenticated";
GRANT ALL ON TABLE "public"."tour_packages" TO "service_role";



GRANT ALL ON TABLE "public"."user_roles" TO "anon";
GRANT ALL ON TABLE "public"."user_roles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_roles" TO "service_role";



GRANT ALL ON TABLE "public"."vendor_locations" TO "anon";
GRANT ALL ON TABLE "public"."vendor_locations" TO "authenticated";
GRANT ALL ON TABLE "public"."vendor_locations" TO "service_role";



GRANT ALL ON TABLE "public"."vendor_payments" TO "anon";
GRANT ALL ON TABLE "public"."vendor_payments" TO "authenticated";
GRANT ALL ON TABLE "public"."vendor_payments" TO "service_role";



GRANT ALL ON TABLE "public"."vendors" TO "anon";
GRANT ALL ON TABLE "public"."vendors" TO "authenticated";
GRANT ALL ON TABLE "public"."vendors" TO "service_role";



GRANT ALL ON TABLE "public"."yellow_app_sync_log" TO "anon";
GRANT ALL ON TABLE "public"."yellow_app_sync_log" TO "authenticated";
GRANT ALL ON TABLE "public"."yellow_app_sync_log" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































