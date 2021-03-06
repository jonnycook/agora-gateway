map = 
	Product:
		'products'
	ProductVariant:
		'product_variants'
	Decision:
		'decisions'
	Composite:
		'composites'
	Bundle:
		'bundles'
	Session:
		'sessions'
	List:
		'lists'
	Descriptor:
		'descriptors'
	ObjectReference:
		'object_references'
	FeedbackPage:
		'feedback_pages'

graph =
	object_references:
		root_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		bundle_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		list_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		session_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		belt_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table


	decisions:
		list_id:
			table:'lists'
			owns:true

		decision_elements:
			field: 'decision_id'
			owns:true
			# filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		decision_suggestions:
			field: 'decision_id'
			owns:true

		feedback_pages:
			field: 'decision_id'
			owns:true

		root_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		bundle_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		list_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		session_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		belt_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table


	decision_elements:
		decision_id:
			table: 'decisions'
			owner:true

	decision_suggestions:
		decision_id:
			table: 'decisions'
			owner:true

	lists:
		list_elements:
			field: 'list_id'
			owns:true

		decisions:
			field: 'list_id'
			owner:true

	list_elements:
		list_id:
			owner:true
			table: 'lists'
		element_id:
			table: (record) -> map[record.element_type]
			owns: (record) -> !(record.element_type in ['Product', 'ProductVariant'])


	bundles:
		root_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		bundle_elements: [
			{
				field: 'element_id'
				owner:true
				filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table
			},
			{
				field: 'bundle_id'
				owns:true
			}
		]
		list_elements:
			field: 'element_id'
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

			owner:true

		session_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		belt_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table


	sessions:
		session_elements:
			field: 'session_id'
			owns:true

		root_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

		belt_elements:
			field: 'element_id'
			owner:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table


	session_elements:
		session_id:
			owner:true
			table: 'sessions'
		element_id:
			table: (record) -> map[record.element_type]
			owns: (record) -> !(record.element_type in ['Product', 'ProductVariant'])

	belts:
		root:true
		belt_elements:
			field: 'belt_id'
			owns:true

	belt_elements:
		belt_id:
			owner:true
			table: 'belts'
		element_id:
			table: (record) -> map[record.element_type]
			owns: (record) -> !(record.element_type in ['Product', 'ProductVariant'])

	bundle_elements:
		bundle_id:
			owner:true
			table: 'bundles'
		element_id:
			table: (record) -> map[record.element_type]
			owns: (record) -> !(record.element_type in ['Product', 'ProductVariant'])

	root_elements:
		root:true
		element_id:
			table: (record) -> map[record.element_type]
			owns: (record) -> !(record.element_type in ['Product', 'ProductVariant'])	

	activity:
		# inGraph:false
		object_id:
			table: (record) -> map[record.object_type]
			onwer:true

	feedback_pages:
		decision_id:
			table: 'decisions'
			owner:true

		feedback_items:
			field: 'feedback_page_id'
			owns:true

		feedback_comments:
			field: 'feedback_page_id'
			owns:true

		feedback_page_reference_items:
			field: 'feedback_page_id'
			owns:true

	feedback_page_reference_items:
		feedback_page_id:
			table: 'feedback_pages'
			owner:true

	feedback_items:
		feedback_page_id:
			table:'feedback_pages'
			owner:true

		feedback_item_replies:
			field:'feedback_item_id'
			owns:true

	feedback_item_replies:
		leaf:true
		feedback_item_id:
			table: 'feedback_items'
			owner:true

	feedback_comments:
		feedback_page_id:
			table:'feedback_pages'
			owner:true

		feedback_comment_replies:
			field:'feedback_comment_id'
			owns:true

	feedback_comment_replies:
		feedback_comment_id:
			table: 'feedback_comments'
			owner:true

module.exports = graph