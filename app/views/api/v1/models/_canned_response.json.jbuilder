json.id canned_response.id
json.short_code canned_response.short_code
json.content canned_response.content
json.account_id canned_response.account_id
json.created_at canned_response.created_at
json.updated_at canned_response.updated_at
if canned_response.created_by
  json.created_by do
    json.id canned_response.created_by.id
    json.name canned_response.created_by.available_name
  end
else
  json.created_by nil
end
