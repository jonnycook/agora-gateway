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

	decisions:
		list_id:
			table:'lists'
			owns:true

		decision_elements:
			field: 'decision_id'
			owns:true
			filter: (table, record, otherRecord) -> map[otherRecord.element_type] == table

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


	decision_elements:
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



module.exports = graph