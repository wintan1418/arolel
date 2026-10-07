# rubyzip 3 writes zip64 local headers (version 4.5, 0xFFFFFFFF sizes plus a
# zip64 extra field) for every entry by default. Word tolerates that, but
# LibreOffice refuses to open such DOCX files ("source file could not be
# loaded"), and nothing we produce comes near the 4GB zip64 threshold:
# document conversions are capped at 25MB. Write plain zip entries instead.
require "zip"

Zip.write_zip64_support = false
