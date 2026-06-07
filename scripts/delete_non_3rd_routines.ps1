$key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxdGJudHV5b3JuandxcXp3cmR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxNjA2NTAsImV4cCI6MjA5NDczNjY1MH0.X0PaWfIEO0GC9sDbrPchb_-Nb_PHfXIybh3Ql-FQclc'
$headers = @{
  apikey = $key
  Authorization = "Bearer $key"
  Prefer = 'return=representation'
}
$uri = 'https://cqtbntuyornjwqqzwrdy.supabase.co/rest/v1/class_routine_slots?semester=neq.3&select=id'
try {
  $response = Invoke-WebRequest -Uri $uri -Method DELETE -Headers $headers
  Write-Output "Status: $($response.StatusCode)"
  Write-Output $response.Content
} catch {
  Write-Output "Error: $($_.Exception.Message)"
  if ($_.ErrorDetails.Message) { Write-Output $_.ErrorDetails.Message }
}
