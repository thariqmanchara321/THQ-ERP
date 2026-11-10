DO $fix$
DECLARE
  v_sql text;
BEGIN
  SELECT pg_get_functiondef('public.gst_gstr3b_preview_v600(uuid,uuid,date,date)'::regprocedure)
  INTO v_sql;

  IF position('interval ''1 month-1 day''' in v_sql)=0 THEN
    RAISE EXCEPTION 'Expected GSTR-3B interval pattern not found';
  END IF;

  v_sql:=replace(
    v_sql,
    'interval ''1 month-1 day''',
    'interval ''1 month'' - interval ''1 day'''
  );

  EXECUTE v_sql;
END
$fix$;