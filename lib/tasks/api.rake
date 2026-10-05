namespace :api do
  desc "Write docs/api/openapi-v1.json from the code: the published version the compatibility test compares with (only after an additive change)"
  task openapi: :environment do
    path = Rails.root.join("docs/api/openapi-v1.json")
    FileUtils.mkdir_p(path.dirname)
    path.write(JSON.pretty_generate(Api::V1::OpenApi.document) + "\n")
  end
end
