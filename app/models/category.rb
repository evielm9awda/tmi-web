class Category

	include ActiveGraph::Node
	
	property :name
	property :context
	
	validates :name, presence: true
	validates :context, presence: true

	has_many :out, :codes, rel_class: :CategorizedAs, dependent: :delete_orphans

	PROMPT_INITIALIZE = %{ 
		You are a social researcher doing data analysis. Please generate a list of the 20 most relevant themes from the following list of codes. The themes should be all lowercase and contain no punctuation. Codes should be stripped of quotation marks. Return each code with an array of its categories in JSON format. Use this JSON as the format:
		
		{ 
			"themes" : [
				{ 
					"theme": "foo",
					"codes": [ "bar", "bat", "baz"]
				}
			]
		}
		
		The codes are as follows: 
	}

	def self.enqueue_category_extractor_job(context)
		CategoryExtractorJob.perform_async(context)
	end

	def self.from_context(context)
		codes = Code.where(context: context)
		client = OpenAI::Client.new
	
		response = client.chat(
			parameters: {
				model: "gpt-4o",
				response_format: { type: "json_object" },
				messages: [{ role: "user", content: "#{PROMPT_INITIALIZE} #{codes.map(&:name).join(",")}" }],
				temperature: 0.7,
			}
		)	

		data = JSON.parse(response.dig("choices", 0, "message", "content"))['themes']

		Category.where(context: context).destroy_all

		data.each do |record|
			category = Category.find_or_create_by(name: record['theme'], context: context)
			record['codes'].each do |v|
				codes.select{ |code| record['codes'].include? code.name }.each{ |code| CategorizedAs.create(from_node: category, to_node: code )}
			end
		end

	end

end 
