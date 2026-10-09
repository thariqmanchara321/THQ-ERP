begin;
do $$ begin
if not private.accounting_search_v702('{"lines":[{"account_code":"1000"}]}','1000') then raise exception 'Numeric account code search';end if;
if not private.accounting_search_v702('{"payment_reference":"12345"}','12345') then raise exception 'Numeric payment reference search';end if;
if not private.accounting_search_v702('{"amount":2500}','₹2,500') then raise exception 'Formatted amount search';end if;
if private.accounting_search_v702('{"amount":12500}','2500') then raise exception 'Amount search must be exact';end if;
end $$;
select '4 numeric search assertions passed' result;
rollback;
