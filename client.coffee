Comments = require 'comments'
Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Icon = require 'icon'
Modal = require 'modal'
Obs = require 'obs'
App = require 'app'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
{tr} = require 'i18n'
Time = require 'time'
Event = require 'event'
Shared = require 'shared'
Toast = require 'toast'

balances = Obs.create {}

exports.render = ->

	req0 = Page.state.get(0)
	if req0 is 'new' || (Db.shared.get('setupFirst') and App.ownerId() is App.userId())
		renderEditOrNew()
		return
	if req0 is 'balances'
		calculateBalances()
		renderBalances()
		return
	if +req0 and Page.state.get(1) is 'edit'
		renderEditOrNew +req0
		return
	if +req0
		renderView +req0
		return
	calculateBalances()
	renderHome()

renderHome = !->
	Comments.enable
		messages:
			settleStart: (c) -> tr("%1 started a settle", c.user)
			settleCancel: (c) -> tr("%1 canceled the settle", c.user)
			settleDone: (c) -> tr("%1 finished the settle!", c.user)
			settleRemind: (c) -> tr("Reminder: there are balances to settle")

	Page.setCardBackground();
	Event.markRead(["transaction"])
	# Balances
	Dom.section !->
		Dom.div !->
			balance = balances.get(App.userId())||0
			Dom.style Box: 'horizontal'
			Dom.div !->
				Dom.text tr("Show all balances")
				Dom.style
					Flex: true
					color: App.colors().highlight
					marginTop: '1px'
			Dom.div !->
				Dom.text "You:"
				Dom.style
					textAlign: 'right'
					margin: '1px 10px 0 0'
			Dom.div !->
				Dom.style
					fontWeight: "bold"
					fontSize: '120%'
					textAlign: 'right'
				stylePositiveNegative(balance)
				Dom.text formatMoney(balance)
		Dom.onTap !->
			Page.nav ['balances']
		Dom.style padding: '16px'

	Obs.observe !->
		settleO = Db.shared.ref('settle')
		if settleO.count().get() > 0
			renderSettlePane(settleO)
		else if getTotalBalance() isnt 0
			Dom.section !->
				Dom.style padding: '16px'
				Dom.div !->
					Dom.style color: App.colors().highlight
					Dom.text tr("Settle balances")
				Dom.div !->
					Dom.style fontSize: '80%', fontWeight: "normal", marginTop: '3px'
					Dom.text tr("Ask people to pay their debts")
				Dom.onTap !->
					Modal.confirm tr("Start settle?"), tr("People with a negative balance are asked to pay up. People with a positive balance need to confirm receipt of the payments."), !->
						Server.call 'settleStart'


	Ui.list !->
		# Add new transaction
		Ui.item !->
			Dom.text "+ Add transaction"
			Dom.style
				color: App.colors().highlight
			Dom.onTap !->
				Page.nav ['new']
		# Latest transactions
		if Db.shared.count("transactions").get() isnt 0
			Db.shared.iterate 'transactions', (tx) !->
				Ui.item !->
					Dom.style padding: '10px 8px 10px 8px'
					Dom.div !->
						Dom.style Box: 'horizontal', width: '100%'
						Dom.div !->
							Dom.style Flex: true
							Event.styleNew tx.get('created')
							if tx.get('type') is 'settle'
								Dom.text tr("Settle payment")
							else
								Dom.text capitalizeFirst(tx.get('text'))
							Dom.style fontWeight: "bold"
							Dom.div !->
								Dom.style fontSize: '80%', fontWeight: "normal", marginTop: '3px'
								byIds = (id for id of tx.get('by'))
								forIds = (id for id of tx.get('for'))
								forText = if tx.get('type') is 'settle' then formatGroup(forIds, false) else tr("%1 person|s", tx.count('for').get())
								Dom.text tr("%1 by %2 for %3", formatMoney(tx.get('total')), formatGroup(byIds, false), forText)

						# Your share
						Dom.div !->
							Box: 'vertical'
							Dom.style textAlign: 'right', paddingLeft: '10px'
							Dom.div !->
								share = calculateShare(tx, App.userId())
								stylePositiveNegative(share)
								Dom.text formatMoney(share)
								if share is 0
									Dom.style color: '#999999'
							# Number of events on the transaction (comments)
							Dom.div !->
								Dom.style margin: '12px -4px 0 0'
								Event.renderBubble [tx.key()]


					Dom.onTap !->
						Page.nav [tx.key()]
			, (tx) -> -tx.key()

renderBalances = !->
	Page.setTitle tr("All balances")
	Dom.h2 tr("Balances")
	renderItem = (userId, balance) !->
		Ui.item !->
			stylePositiveNegative(balance)
			Ui.avatar App.userAvatar(userId),
				onTap: (!-> App.showMemberInfo(userId))
				style: marginRight: "12px"
			Dom.div !->
				Dom.style Flex: true
				Dom.div formatName(userId, true)
			Dom.div !->
				Dom.text formatMoney(balance)
	balances.iterate (b) !->
		renderItem b.key(), b.get()
	, (b) ->
		(b || Infinity)

	# Full up with users not in balances
	App.users.iterate (user) !->
		renderItem user.key(), 0
	, (user) ->
		true if !balances.get(user.key())

	settleO = Db.shared.ref('settle')
	if !settleO.isHash()
		Obs.observe !->
			if getTotalBalance() isnt 0
				Dom.div !->
					Ui.lightButton tr("Settle"), !->
						Modal.confirm tr("Start settle?"), tr("People with a negative balance are asked to pay up. People with a positive balance need to confirm receipt of the payments."), !->
							Server.call 'settleStart'
							Page.back()

# Render a transaction
renderView = (txId) !->
	transaction = Db.shared.ref("transactions", txId)
	# Check for incorrect transaction ids
	if !transaction.isHash()
		Ui.emptyText tr("No such transaction")
		return
	Page.setTitle "Transaction"
	Event.showStar tr("this transaction")

	# Set the page actions
	Page.setActions
		icon: 'edit'
		label: "Edit transaction"
		action: !->
			Page.nav [transaction.key(), 'edit']

	# Render paid by items
	Dom.div !->
		Dom.style fontSize: "150%"
		if Db.shared.get("transactions", txId, "type") is 'settle'
			Dom.text tr("Settle payment")
		else
			Dom.text transaction.get("text")
	Dom.div !->
		Dom.style fontSize: '80%'
		created = Db.shared.get("transactions", txId, "created")
		updated = Db.shared.get("transactions", txId, "updated")
		if created?
			creatorId = Db.shared.get("transactions", txId, "creatorId")
			if creatorId>=0
				Dom.text tr("Added by %1 ", App.userName(creatorId))
			else
				Dom.text tr("Generated by the app ")
			Time.deltaText created
			if updated?
				Dom.text tr(", edited ")
				Time.deltaText updated
	Dom.div !->
		Dom.style marginTop: "15px"
		Dom.h2 tr("Paid by")
		renderBalanceSplitSection(transaction.get("total"), transaction.ref("by"), transaction.key())

	# Render paid for items
	Dom.div !->
		Dom.style marginTop: "15px"
		Dom.h2 tr("Paid for")
		renderBalanceSplitSection(transaction.get("total"), transaction.ref("for"), transaction.key())

	Comments.enable
		legacyStore: txId
		messages:
			edited: (c) -> tr("%1 edited the transaction",c.user)

renderBalanceSplitSection = (total, path, transactionNumber) !->
	remainder = Obs.create(total)
	lateRemainder = Obs.create(total)
	totalShare = Obs.create(0)
	usersList = Obs.create {}
	distribution = Obs.create {}
	Obs.observe !->
		path.iterate (user) !->
			userKey = user.key()
			usersList.set userKey, true
			Obs.onClean !->
				usersList.remove userKey
			if (user.get()+"") is "true"
				totalShare.modify((v) -> v+100)
				Obs.onClean !->
					totalShare.modify((v) -> v-100)
			else if (user.get()+"").substr(-1) is "%"
				amount = user.get()+""
				percent = (+(amount.substr(0, amount.length-1)))
				totalShare.modify((v) -> v+percent)
				Obs.onClean !->
					totalShare.modify((v) -> v-percent)
	Obs.observe !->
		distribution.set Shared.remainderDistribution(usersList.peek(), lateRemainder.get(), transactionNumber)
	Obs.observe !->
		path.iterate (user) !->
			amount = user.get()
			number = 0
			suffix = undefined
			if amount is true
				number = Math.round(remainder.get()/totalShare.get()*100)
				lateRemainder.modify((v) -> v-number)
				Obs.onClean !->
					lateRemainder.modify((v) -> v+number)
			else if (amount+"").substr(-1) is "%"
				amount = amount+""
				percent = +(amount.substr(0, amount.length-1))
				number = Math.round(remainder.get()/totalShare.get()*percent)
				lateRemainder.modify((v) -> v-number)
				Obs.onClean !->
					lateRemainder.modify((v) -> v+number)
				suffix = percent+"%"
			else
				number = +amount
				remainder.modify (v) -> v-number
				lateRemainder.modify (v) -> v-number
				suffix = "fixed"
				Obs.onClean !->
					remainder.modify((v) -> v+number)
					lateRemainder.modify((v) -> v+number)
			Ui.item !->
				Ui.avatar App.userAvatar(user.key()),
					onTap: (!-> App.showMemberInfo(user.key()))
					style: marginRight: "10px"
				Dom.div !->
					Dom.style Flex: true
					Dom.div formatName(user.key(), true)
				Dom.div !->
					Dom.style textAlign: 'right'
					Dom.div !->
						Dom.text formatMoney(number+(distribution.get(user.key())||0))
					if suffix isnt undefined
						Dom.div !->
							Dom.style fontSize: '80%'
							Dom.text "("+suffix+")"
		, (amount) ->
			# Sort static on top, then percentage, then remainder
			return getSortValue(amount.get())

# Render a transaction edit page
renderEditOrNew = (editId) !->
	if editId
		edit = Db.shared.ref('transactions', editId)
		if !edit.isHash()
			Ui.emptyText tr("No such transaction")
			return

		Page.setTitle "Edit transaction"
	else
		Page.setTitle "New transaction"

	# Current form total
	totalO = Obs.create 0
	byO = undefined
	forO = undefined
	multiplePaidBy = Obs.create(false)
	# Description and amount input
	Obs.observe !->
		# Check if there is an ongoing settle
		if Db.shared.count("settle").get()
			###
			Dom.div !->
				Dom.style
					margin: '0 0 8px'
					background: '#888'
					color: '#fff'
					fontSize: '80%'
					padding: '8px'
					fontStyle: 'italic'
			###
			Ui.top !->
				Dom.text tr("There is an ongoing settle. ")
				if editId
					Dom.text tr("It will not include changes to this transaction.")
				else
					Dom.text tr("It will not include new transactions.")


		Dom.div !->
			Dom.style Box: 'top'
			Dom.div !->
				Dom.style Flex: true
				defaultValue = undefined
				if Db.shared.get("transactions", editId, "type") is 'settle'
					defaultValue = "Settle payment"
				else if edit
					defaultValue = edit.get('text')
				else if Db.shared.get('setupFirst')
					defaultValue = App.title()

				hideDescr = Db.shared.get('setupFirst') and App.userId() is App.ownerId()
				Form.input
					name: 'text'
					value: defaultValue
					text: tr("Description")
					style: display: (if hideDescr then 'none' else 'block')
		Dom.div !->
			Dom.style fontSize: '80%'
			created = Db.shared.get("transactions", editId, "created")
			updated = Db.shared.get("transactions", editId, "updated")
			if created?
				creatorId = Db.shared.get("transactions", editId, "creatorId")
				if creatorId>=0
					Dom.text tr("Added by %1 ", App.userName(creatorId))
				else
					Dom.text tr("Generated by the app ")
				Time.deltaText created
				if updated?
					Dom.text tr(", last edited ")
					Time.deltaText updated
			# No amount entered
			Form.condition (values) ->
				if (not (values.text?)) or values.text.length < 1
					return tr("Enter a description")

		Dom.div !->
			Dom.style marginTop: '20px'
		Dom.h2 tr("Paid by")
		byO = Obs.create {}
		if edit
			byO.set edit.get('by')
		else
			byO.set App.userId(), 0
		multiplePaidBy.set(byO.count().peek() > 1)
		# Set the total
		Obs.observe !->
			byO.iterate (user) !->
				oldValue = parseInt(user.get())
				totalO.modify((v) -> v + oldValue)
				Obs.onClean !->
					totalO.modify((v) -> v - oldValue)
		# Save data in pagestate
		[handleChange] = Form.makeInput
			name: 'by'
			value: byO.peek()
		Obs.observe !->
			handleChange byO.get()
		# Render page
		Obs.observe !->
			if not multiplePaidBy.get()
				Ui.item !->
					userKey = ""
					byO.iterate (user) !->
						userKey = user.key()
					Ui.avatar App.userAvatar(userKey),
						onTap: (!-> App.showMemberInfo(userKey))
						style: marginRight: "10px"
					Dom.div !->
						Dom.style Flex: true
						Dom.div formatName(userKey, true)
					Dom.div !->
						currency = "€"
						if Db.shared.get("currency")
							currency = Db.shared.get("currency")
						Dom.text currency
						Dom.style
							margin: '-14px 5px 0 0'
							fontSize: '21px'
					inputField = undefined
					centField = undefined
					Dom.div !->
						Dom.style width: '80px', margin: '-20px 0 -20px 0'
						inputField = Form.input
							name: 'paidby'
							type: 'number'
							text: '0'
							style:
								textAlign: 'right'
							onChange: (v) !->
								if v and inputField and centField
									result = wholeAndCentToCents(inputField.value(), centField.value())
									if !isNaN(result)
										byO.set(userKey, result)
						if inputField?
							if byO.peek(userKey)
								inputField.value (byO.peek(userKey) - byO.peek(userKey)%100)/100
							else
								inputField.value null
					Dom.div !->
						Dom.style
							width: '10px'
							fontSize: '175%'
							padding: '12px 0 0 5px'
							margin: '-20px 0 -20px 0'
						Dom.text ","
					Dom.div !->
						Dom.style width: '60px', margin: '-20px 0 -20px 0'
						centField = Form.input
							name: 'paidby2'
							type: 'number'
							text: '00'
							onChange: (v) !->
								if v<0
									centField.value(0)
								if v and inputField and centField
									result = wholeAndCentToCents(inputField.value(), centField.value())
									if !isNaN(result)
										byO.set(userKey, result)
						if centField?
							if (b = byO.peek(userKey)) and (mod = b%100) isnt 0
								centField.value mod
							else
								centField.value null
					Dom.on 'keydown', (evt) !->
						if evt.getKeyCode() in [188,190,110] # comma and dot
							centField.focus()
							centField.select()
							evt.kill()
					,true
			else
				# Set form input
				Obs.observe !->
					Dom.div !->
						#Dom.style margin: '5px -5px 0 -5px'
						App.users.iterate (user) !->
							amount = byO.get(user.key())
							number = 0
							suffix = undefined
							if amount
								number = +amount
							Dom.div !-> # Aligning div
								Dom.style
									display: 'inline-block'
									padding: '5px'
									boxSizing: 'border-box'
								items = 2
								while (Page.width()-16)/items > 180
									items++
								items--
								Dom.style width: 100/items+"%"
								Dom.div !-> # Bock div
									Dom.style
										backgroundColor: '#f2f2f2'
										padding: '5px'
										Box: 'horizontal'
										_borderRadius: '2px'
										border: '1px solid #e0e0e0'
									Dom.cls 'selectBlock'
									Dom.onTap
										cb: !->
											value = undefined
											oldValue = undefined
											update = Obs.create(false)
											Obs.observe !->
												update.get()
												if oldValue?
													number = +oldValue
													if (not (isNaN(number)))
														if number is 0
															byO.remove user.key()
														else
															byO.set user.key(), number
													else
														Modal.show "Incorrect input: \""+oldValue+"\", use a number"
												# Do something
											Modal.show tr("Amount paid by %1?", formatName(user.key())), !->
												Dom.div !->
													Dom.style Box: "horizontal"
													Dom.div !->
														currency = "€"
														if Db.shared.get("currency")
															currency = Db.shared.get("currency")
														Dom.text currency
														Dom.style
															margin: '14px 5px 0px 0px'
															fontSize: '21px'
													inputField = undefined
													centField = undefined
													Dom.div !->
														Dom.style width: '80px'
														inputField = Form.input
															name: 'paidby'
															type: 'number'
															text: '0'
															style: {textAlign: 'right'}
															onChange: (v) !->
																if v and inputField and centField
																	oldValue = value
																	value = wholeAndCentToCents(inputField.value(), centField.value())
														if inputField?
															if byO.peek(user.key())
																inputField.value (byO.peek(user.key()) - (byO.peek(user.key())%100))/100
															else
																inputField.value null
													Dom.div !->
														Dom.style
															width: '10px'
															fontSize: '175%'
															padding: '23px 0 0 4px'
														Dom.text ","
													Dom.div !->
														Dom.style width: '60px'
														centField = Form.input
															name: 'paidby2'
															type: 'number'
															text: '00'
															onChange: (v) !->
																return if not centField?
																if v<0
																	centField.value(0)
																if inputField
																	oldValue = value
																	value = wholeAndCentToCents(inputField.value(), centField.value())
														if centField?
															if byO.peek(user.key()) and (mod = byO.peek(user.key())%100) isnt 0
																centField.value mod
															else
																centField.value null
													Dom.on 'keydown', (evt) !->
														if evt.getKeyCode() in [188,190,110] # comma and dot
															centField.focus()
															centField.select()
															evt.kill()
													,true
											, (value) !->
												if value isnt null and value isnt undefined and value is 'ok'
													update.set(true)
											, ['ok', "Ok", 'cancel', "Cancel"]
									Dom.style
										fontWeight: if amount then 'bold' else ''
									Ui.avatar App.userAvatar(user.key()), style: marginRight: "10px"
									Dom.div !->
										Dom.style
											Flex: true
										Dom.div !->
											Dom.style
												Flex: true
												overflow: 'hidden'
												textOverflow: 'ellipsis'
												whiteSpace: 'nowrap'
												marginTop: '10px'
											if amount
												Dom.style marginTop: "0"
											Dom.text formatName(user.key(), true)
										if amount
											Dom.div !->
												Dom.style Box: 'horizontal'
												Dom.div !->
													Dom.style Flex: true
													Dom.text formatMoney(number)
												Dom.div !->
													Icon.render
														data: 'good2'
														size: 20
														color: '#080'

		Obs.observe !->
			if not multiplePaidBy.get() and App.users.count().get() > 1
				Dom.div !->
					Dom.style
						textAlign: 'center'
						color: App.colors().highlight
						fontSize: "80%"
						padding: "7px"
						margin: "0 0 -8px 0"
					Dom.text tr("Add other(s)")
					Dom.onTap !->
						multiplePaidBy.set(true)

		Dom.div !->
			Dom.style marginTop: '20px'
		Dom.h2 tr("Paid for")
		# Setup remainder
		remainder = Obs.create(0)
		lateRemainder = Obs.create(0)
		Obs.observe !->
			oldTotal = totalO.peek()
			remainder.modify((v)->v+totalO.get())
			lateRemainder.modify((v)->v+totalO.get())
			Obs.onClean !->
				remainder.modify((v)->v-oldTotal)
				lateRemainder.modify((v)->v-oldTotal)
		# Setup for
		forO = Obs.create {}
		if edit
			forO.set edit.get('for')
		if Db.shared.get('setupFirst')
			App.users.iterate (user) !->
				forO.set(user.key(), true)
		[handleChange] = Form.makeInput
			name: 'for'
			value: forO.peek()
		Obs.observe !->
			handleChange forO.get()
		# Setup totalshare
		totalShare = Obs.create 0
		usersList = Obs.create {}
		distribution = Obs.create {}
		Obs.observe !->
			transactionNumber = (Db.shared.get('transactionId')||0)+1
			transactionNumber = editId if editId
			distribution.set Shared.remainderDistribution(usersList.peek(), lateRemainder.get(), transactionNumber)
		# Select/deselect all button
		Obs.observe !->
			users = App.users.count().get()
			selected = forO.count().get()
			Dom.div !->
				Dom.text "Select all" if selected < users
				Dom.text "Deselect all" if selected is users
				Dom.style
					float: 'right'
					margin: '-34px 6px -20px 0'
					padding: '9px 8px 2px 8px'
					color: App.colors().highlight
					fontSize: '80%'
				Dom.onTap !->
					if selected < users
						App.users.iterate (user) !->
							if forO.peek(user.key()) is undefined
								forO.set(user.key(), true)
					else
						forO.set {}
		# Render page
		Obs.observe !->
			Dom.div !->
				#Dom.style margin: '5px -5px 0 -5px', _userSelect: 'none'
				Dom.style MarginPolicy: 'pad', padding: '0 8px'
				App.users.iterate (user) !->
					amount = forO.get(user.key())
					number = Obs.create 0
					suffix = undefined
					Obs.observe !->
						if amount
							usersList.set user.key(), true
							Obs.onClean !->
								usersList.remove user.key()
							if (amount+"") is "true"
								totalShare.modify((v) -> v+100)
								Obs.onClean !->
									totalShare.modify((v) -> v-100)
								Obs.observe !->
									currentNumber = Math.round((remainder.get())/totalShare.get()*100)
									number.set(currentNumber)
									lateRemainder.modify((v) -> v-currentNumber)
									Obs.onClean !->
										lateRemainder.modify((v) -> v+currentNumber)
							else if (amount+"").substr(-1) is "%"
								amount = amount+""
								percent = +(amount.substr(0, amount.length-1))
								totalShare.modify((v) -> v+percent)
								Obs.onClean !->
									totalShare.modify((v) -> v-percent)
								Obs.observe !->
									currentNumber = Math.round((remainder.get())/totalShare.get()*percent)
									number.set(currentNumber)
									lateRemainder.modify((v) -> v-currentNumber)
									Obs.onClean !->
										lateRemainder.modify((v) -> v+currentNumber)
								suffix = percent+"%"
							else
								number.set(+amount)
								Obs.observe !->
									remainder.modify((v) -> v-number.get())
									lateRemainder.modify((v) -> v-number.get())
									Obs.onClean !->
										remainder.modify((v) -> v+number.get())
										lateRemainder.modify((v) -> v+number.get())
								suffix = "fixed"
					Dom.div !-> # Aligning div
						Dom.style
							display: 'inline-block'
							padding: '5px'
							boxSizing: 'border-box'
						items = 2
						while (Page.width()-16)/items > 180
							items++
						items--
						Dom.style width: 100/items+"%"
						Dom.div !-> # Bock div
							Dom.style
								backgroundColor: '#f2f2f2'
								padding: '5px'
								Box: 'horizontal'
								_borderRadius: '2px'
								border: '1px solid #e0e0e0'
							Dom.cls 'selectBlock'
							Dom.onTap
								cb: !->
									if amount
										forO.set(user.key(), null)
									else
										forO.set(user.key(), true)
								longTap: !->
									value = undefined
									update = Obs.create(false)
									Obs.observe !->
										update.get()
										if value?
											v = value
											amount = +v
											if (v+"").substr(-1) is "%"
												percent = +((v+"").substr(0, v.length-1))
												if isNaN(percent)
													Modal.show "Incorrect percentage: \""+v+"\""
													return
												if percent < 0
													Modal.show "Percentage needs to be a positive number"
													return
												else
													if percent is 0
														forO.remove user.key()
													else
														forO.set user.key(), v
											else if not isNaN(amount)
												if amount is 0
													forO.remove user.key()
												else
													forO.set user.key(), amount
											else
												Modal.show "Please enter a number"
									Modal.show tr("Amount paid for %1?", formatName(user.key())), !->
										procentual = Obs.create (forO.peek(user.key())+"").substr(-1) is "%"
										Obs.observe !->
											if procentual.get()
												Dom.div !->
													Dom.style Box: 'horizontal center'
													Dom.div !->
														Dom.style width: '80px'
														defaultValue = undefined
														if (forO.peek(user.key())+"").substr(-1) is "%"
															defaultValue = (forO.peek(user.key())+"").substr(0, (forO.peek(user.key())+"").length-1)
														inputField = Form.input
															name: 'paidForPercent'+user.key()
															text: '100'
															value: defaultValue
															type: 'number'
															onChange: (v) ->
																if v
																	value = v+"%"
																return
													Dom.div !->
														Dom.style
															margin: '14px 5px 0px 0px'
															fontSize: '21px'
														Dom.text "%"
											else
												Dom.div !->
													Dom.style Box: "horizontal center"
													Dom.div !->
														currency = "€"
														if Db.shared.get("currency")
															currency = Db.shared.get("currency")
														Dom.text currency
														Dom.style
															margin: '14px 5px 0px 0px'
															fontSize: '21px'
													inputField = undefined
													centField = undefined
													Dom.div !->
														Dom.style width: '80px'
														inputField = Form.input
															name: 'paidby'
															type: 'number'
															text: '0'
															style: {textAlign: 'right'}
															onChange: (v) !->
																if v and inputField? and centField?
																	value = wholeAndCentToCents(inputField.value(), centField.value())
														if inputField?
															if forO.peek(user.key()) and (forO.peek(user.key())+"") isnt "true"
																inputField.value (forO.peek(user.key()) - (forO.peek(user.key())%100))/100
															else
																inputField.value null
													Dom.div !->
														Dom.style
															width: '10px'
															fontSize: '175%'
															padding: '23px 0 0 4px'
														Dom.text ","
													Dom.div !->
														Dom.style width: '60px'
														centField = Form.input
															name: 'paidby2'
															type: 'number'
															text: '00'
															onChange: (v) !->
																if v<0
																	centField.value(0)
																if inputField? and centField?
																	value = wholeAndCentToCents(inputField.value(), centField.value())
														if centField?
															if forO.peek(user.key()) and forO.peek(user.key())%100 isnt 0
																centField.value forO.peek(user.key())%100
															else
																centField.value null
													Dom.on 'keydown', (evt) !->
														if evt.getKeyCode() in [188,190,110] # comma and dot
															centField.focus()
															centField.select()
															evt.kill()
													,true
										Dom.br()
										Dom.div !->
											Dom.style
												display: 'inline-block'
												color: App.colors().highlight
												padding: "5px"
											if procentual.get()
												Dom.style fontWeight: 'normal'
											else
												Dom.style fontWeight: 'bold'
											Dom.text "Fixed amount"
											Dom.onTap !->
												procentual.set false
										Dom.text " | "
										Dom.div !->
											Dom.style
												display: 'inline-block'
												color: App.colors().highlight
												padding: "5px"
											if !procentual.get()
												Dom.style fontWeight: 'normal'
											else
												Dom.style fontWeight: 'bold'
											Dom.text "Percentage"
											Dom.onTap !->
												procentual.set true
									, (value) !->
										if value and value is 'ok'
											update.set(true)
									, ['cancel', "Cancel", 'ok', "Ok"]
							Dom.style
								fontWeight: if amount then 'bold' else ''
								clear: 'both'
							Ui.avatar App.userAvatar(user.key()), style: marginRight: "10px"
							Dom.div !->
								Dom.style
									Flex: true
								Dom.div !->
									Dom.style
										Flex: true
										overflow: 'hidden'
										textOverflow: 'ellipsis'
										whiteSpace: 'nowrap'
										marginTop: '10px'
									if amount
										Dom.style marginTop: "0"
									Dom.text formatName(user.key(), true)
								if amount
									Dom.div !->
										Dom.style Box: 'horizontal'
										Dom.div !->
											Dom.style Flex: true
											Dom.text formatMoney(number.get()+(distribution.get(user.key())||0))
											Dom.style
												fontWeight: 'normal'
												fontSize: '90%'
											if suffix isnt undefined
												Dom.div !->
													Dom.style
														fontWeight: 'normal'
														fontSize: '80%'
														display: 'inline-block'
														marginLeft: "5px"
													Dom.text "("+suffix+")"
										Dom.div !->
											Icon.render
												data: 'good2'
												size: 20
												color: '#080'
		Form.condition () ->
			if totalO.peek() is 0
				text = "Total sum cannot be zero"
				if Db.shared.peek("transactions", editId)?
					text += " (remove it instead)"
				return tr(text)

			divide = []
			remainderTemp = totalO.peek()
			completeShare = 0
			for userId,amount of forO.peek()
				if (amount+"").substr(-1) is "%"
					amount = amount+""
					percent = +(amount.substring(0, amount.length-1))
					completeShare += percent
					divide.push userId
				else if (""+amount) is "true"
					divide.push userId
					completeShare += 100
				else
					number = +amount
					amount = Math.round(amount*100.0)/100.0
					remainderTemp -= amount
			if remainderTemp isnt 0 and divide.length > 0
				while userId = divide.pop()
					raw = forO.peek(userId)
					percent = 100
					if (raw+"").substr(-1) is "%"
						raw = raw+""
						percent = +(raw.substring(0, raw.length-1))
					amount = Math.round((remainderTemp*100.0)/completeShare*percent)/100.0
				remainderTemp = 0
			if remainderTemp isnt 0
				return tr("Paid by and paid for do not add up")
	Dom.div !->
		Dom.style
			textAlign: 'center'
			fontStyle: 'italic'
			padding: '3px'
			color: '#aaa'
			fontSize: '85%'
		Dom.text tr("Hint: long-tap on a user to set a specific amount or percentage")

	if Db.shared.peek("transactions", editId)?
		Page.setActions
			icon: 'delete'
			label: "Remove transaction"
			action: !->
				Modal.confirm "Remove transaction",
					"Are you sure you want to remove this transaction?",
					!->
						Server.call 'removeTransaction', editId
						# Back to the main page
						Page.back()
						Page.back()

	Form.setPageSubmit (values) !->
		Page.nav()
		result = {}
		result['total'] = totalO.peek()
		result['by'] = byO.peek()
		result['for'] = forO.peek()
		result['text'] = values.text
		Server.sync 'transaction', editId, result, !->
			id = Db.shared.modify 'transactionId', (v) -> (v||0)+1
			result["creatorId"] = App.userId()
			result["created"] = (new Date()/1000)
			Db.shared.set "transactions", id, result

# Sort static on top, then percentage, then remainder, then undefined
getSortValue = (key) ->
	if (key+"").substr(-1) is "%"
		return 0
	else if (key+"") is "true"
		return 1
	else if (key is undefined or not (key?))
		return 10
	else
		return -1

renderSettlePane = (settleO) !->
	Ui.list !->
		Form.label !->
			Dom.text tr("Settle")
		Dom.div !->
			Dom.style
				Flex: true
				margin: '8px 0 4px 0'
				background: '#888'
				color: '#fff'
				fontSize: '80%'
				padding: '8px'
				fontStyle: 'italic'

			infoRequired = false
			if account = Db.shared.get('accounts', App.userId())
				Dom.text tr("Your bank account: %1", account.toUpperCase())
				if name = Db.shared.get("accountNames", App.userId())
					Dom.text " / " + name
				else
					infoRequired = tr("Tap to input account holder name")
				Dom.br()
			else
				infoRequired = tr("Tap to input your bank account number")

			if infoRequired
				Dom.text infoRequired
				Dom.style
					fontWeight: "bold"
					fontStyle: "normal"
					backgroundColor: App.colors().highlight

			Dom.onTap !->
				account = undefined
				name = undefined
				Modal.show tr("Enter account information"), !->
					Dom.div !->
						Dom.text "Account number"
					account = Form.input
						name: 'account'
						type: 'text'
					account.value (if (currentAccount = Db.shared.get("accounts", App.userId()))? then currentAccount.toUpperCase() else "")
					Dom.div !->
						Dom.text "Account holder"
					name = Form.input
						name: 'name'
						type: 'text'
					name.value (if (currentName = Db.shared.get("accountNames", App.userId()))? then currentName else App.userName())
				, (value) !->
					if value and value is 'confirm'
						accountV = account.value()
						nameV = name.value()
						Server.sync "account", accountV, nameV, !->
							Db.shared.set "accounts", App.userId(), accountV
							Db.shared.set "accountNames", App.userId(), nameV
						Toast.show "Account and name set"
				, ['cancel', "Cancel", 'confirm', "Confirm"]
		settleO.iterate (tx) !->
			Ui.item !->
				[from,to] = tx.key().split(':')
				done = tx.get('done')
				amount = tx.get('amount')
				Icon.render
					data: 'good2'
					color: if done then '#777' else '#ccc'
					style: {marginRight: '10px'}
				statusText = undefined
				statusBold = false
				confirmText = undefined
				isTo = +to is App.userId()
				isFrom = +from is App.userId()
				# Determine status text
				if done
					statusBold = isTo
					statusText = tr("%1 paid %2 to %3, waiting for confirmation", formatName(from,true), formatMoney(amount), formatName(to))
				else
					statusBold = isFrom || isTo
					statusText = tr("%1 should pay %2 to %3", formatName(from,true), formatMoney(amount), formatName(to))
				# Determine action text and tap action
				paidToggle = !->
					toggle = !->
						Server.sync 'settlePayed', tx.key(), !->
							tx.modify 'done', (v) -> !v
					if tx.get("done")
						toggle()
					else
						Modal.confirm tr("Confirm payment?"), tr("Are you sure that you want to confirm? This will notify "+App.userName(to))
							, !->
								toggle()

				doneConfirm = !->
					Server.sync 'settleDone', tx.key(), !->
						[from,to] = tx.key().split(':')
						id = Db.shared.modify 'transactionId', (v) -> (v||0)+1
						transaction = {}
						forData = {}
						forData[to] = tx.peek("amount")
						byData = {}
						byData[from] = tx.peek("amount")
						transaction["creatorId"] = -1
						transaction["for"] = forData
						transaction["by"] = byData
						transaction["type"] = "settle"
						transaction["total"] = tx.peek("amount")
						transaction["created"] = (new Date()/1000)
						Db.shared.set "transactions", id, transaction
						Db.shared.remove "settle", tx.key()
				confirmAdminDone = !->
					Dom.onTap !->
						Modal.confirm tr("Confirm as admin?")
							, tr("This will confirm receipt of payment by %1 and move the transaction to the transaction list", formatName(to))
							, !->
								doneConfirm()
				if !isTo and !isFrom
					if App.userIsAdmin()
						confirmText = tr("Tap to confirm this payment as admin")
						confirmAdminDone()
				else if !isTo and isFrom
					if done # sender confirmed
						if App.userIsAdmin()
							confirmText = tr("Waiting for confirmation by %1", formatName(to))
							Dom.onTap !->
								Modal.show tr("(Un)confirm payment?")
									, !->
										Dom.text tr("Do you want to unconfirm that you paid, or (as admin) confirm receipt of payment by %1?", formatName(to))
									, (value) !->
										if value is 'removeSend'
											paidToggle()
										else if value is 'confirmPay'
											doneConfirm()
									, ['cancel', "Cancel", 'removeSend', "Unconfirm", 'confirmPay', "Confirm"]
						else
							confirmText = tr("Waiting for confirmation by %1, tap to cancel", formatName(to))
							Dom.onTap !->
								paidToggle()
					else
						if account = Db.shared.get('accounts', to)
							accountTxt = if !!Form.clipboard and Form.clipboard() then tr("%1 (long press to copy)", account) else tr("%1", account)
							holderTxt = if (holder = Db.shared.get("accountNames", to))? then ", holder: "+holder else ""
							confirmText = tr("Account: %1%2. Tap to confirm your payment to %3.", accountTxt, holderTxt, formatName(to))
						else
							confirmText = tr("Account info missing. Tap to confirm your payment to %1.", formatName(to))
						Dom.onTap
							cb: !-> paidToggle()
							longTap: !->
								if account and !!Form.clipboard and (clipboard = Form.clipboard())
									clipboard(account)
									require('toast').show tr("Account copied to clipboard")
				else if isTo and !isFrom
					confirmText = tr("Tap to confirm receipt of payment")
					Dom.onTap !->
						Modal.confirm tr("Confirm payment received?")
							, tr("Confirming will move the transaction to the transaction list")
							, !-> doneConfirm()
				else
					# Should never occur (incorrect settle)
				Dom.div !->
					Dom.style fontWeight: (if statusBold then 'bold' else ''), Flex: true
					Dom.text statusText
					if confirmText?
						Dom.div !->
							Dom.style fontSize: '80%'
							Dom.text confirmText

		Dom.div !->
			Dom.style textAlign: 'center'
			sentButNotReceived = false
			for k,v of settleO.get()
				if v.done
					sentButNotReceived = true
			if App.userIsAdmin() # serverside this case will not be checked, ah well --Jelmer
				Ui.lightButton tr("Cancel"), !->
					if sentButNotReceived
						Modal.show tr("Cancel not allowed"), tr("Please (un)confirm receipt of sent payments (dark gray checkmarks) before postponing the settle")
					else
						Modal.confirm tr("Cancel settle?")
						, tr("You can start a new settle later")
						, !-> Server.sync 'settleStop', !-> Db.shared.remove 'settle'


formatMoney = (amount) ->
	amount = Math.round(amount)
	currency = "€"
	if Db.shared.get("currency")
		currency = Db.shared.get("currency")
	string = amount/100
	if amount%100 is 0
		string +=".00"
	else if amount%10 is 0
		string += "0"
	return currency+(string)

formatName = (userId, capitalize) ->
	if +userId != App.userId()
		App.userName(userId)
	else if capitalize
		tr("You")
	else
		tr("you")

formatGroup = (userIds, capitalize) ->
	if userIds.length > 3
		userIds[0...3].map(formatName).join(', ') + ' and ' + (userIds.length-3) + ' others'
	else if userIds.length > 1
		userIds[0...userIds.length-1].map(formatName).join(', ') + ' and ' + App.userName(userIds[userIds.length-1])
	else if userIds.length is 1
		formatName(userIds[0], capitalize)

selectUser = (cb) !->
	require('modal').show tr("Select user"), !->
		Dom.style width: '80%'
		Dom.div !->
			Dom.style
				maxHeight: '40%'
				backgroundColor: '#eee'
				margin: '-12px'
			Dom.overflow()
			App.users.iterate (user) !->
				Ui.item !->
					Ui.avatar user.get('avatar')
					Dom.text user.get('name')
					Dom.onTap !->
						cb user.key()
						Modal.remove()
			, (user) ->
				+user.key()
	, false, ['cancel', tr("Cancel")]


exports.renderSettings = !->
	singleMode = Obs.create (if Db.shared?.peek('singleMode') is false then false else true)

	if !Db.shared
		singleCheck = multipleCheck = undefined
		# TODO: replace by radio buttons
		Form.segmented
			name: 'mode'
			value: 'single'
			segments: ['single', tr("Single transaction"), 'multiple', tr("Running balances")]
			description: !->
				showSingle = !Db.shared and singleMode.get()
				Dom.text (if showSingle then tr("People will be asked to pay their share directly") else tr("Balances will be tracked, until a settle is started"))
			onChange: (v) !->
				singleMode.set(v is 'single')

	Obs.observe !->
		showSingle = !Db.shared and singleMode.get()

		if showSingle
			Form.input
				name: '_title'
				text: tr("Transaction description")
				value: App.title()
			Form.condition (values) ->
				if !values._title.trim()
					tr("A description is required")
		else
			Form.label tr("Currency symbol")
			currencyInput = null
			Dom.div !->
				Dom.style Box: 'horizontal'
				text = '€'
				if Db.shared
					if Db.shared.get("currency")
						text = Db.shared.get("currency")
				currencyInput = Form.input
					name: 'currency'
					text: text
					style: padding: '0 4px', width: '35px'
				renderCurrency = (value) !->
					Ui.button !->
						Dom.text value
						Dom.style
							width: "20px"
							fontSize: "125%"
							textAlign: "center"
							padding: "4px 6px"
							margin: "14px 4px 22px"
					, !->
						currencyInput.value(value)
				renderCurrency("€")
				renderCurrency("$")
				renderCurrency("£")


calculateShare = (transaction, id) ->
	calculatePart = (section, total, id) ->
		divide = []
		remainder = total
		totalShare = 0
		for userId,amount of section.peek()
			if (amount+"").substr(-1) is "%"
				amount = amount+""
				percent = +(amount.substring(0, amount.length-1))
				totalShare += percent
				divide.push userId
			else if (""+amount) is "true"
				divide.push userId
				totalShare += 100
			else
				number = +amount
				remainder -= amount
				if (userId+"") is (id+"")
					return amount
		result = 0
		if remainder isnt 0 and divide.length > 0
			lateRemainder = remainder
			while userId = divide.pop()
				raw = section.peek(userId)
				percent = 100
				if (raw+"").substr(-1) is "%"
					raw = raw+""
					percent = +(raw.substring(0, raw.length-1))
				amount = Math.round(remainder/totalShare*percent)
				lateRemainder -= amount
				if (userId+"") is (id+"")
					result = amount

			if lateRemainder isnt 0  # There is something left
				distribution = Shared.remainderDistribution section.peek(), lateRemainder, transaction.key()
				result += (distribution[id]||0)

		return result
	byAmount = calculatePart(transaction.ref('by'), transaction.get('total'), id)
	forAmount = calculatePart(transaction.ref('for'), transaction.get('total'), id)
	result = byAmount - forAmount
	return result

stylePositiveNegative = (amount) !->
	if amount > 0
		Dom.style color: "#080"
	else if amount < 0
		Dom.style color: "#E41B1B"

capitalizeFirst = (string) ->
	return string.charAt(0).toUpperCase() + string.slice(1)

getTotalBalance = ->
	total = Obs.create 0
	balances.iterate (user) !->
		value = user.get()
		total.modify((v) -> (v||0)+Math.abs(value))
		Obs.onClean !->
			total.modify((v) -> (v||0)-Math.abs(value))
	total.get()

wholeAndCentToCents = (whole, cent) ->
	if cent?.length<2
		cent = cent+'0'
	(0|whole)*100 + (0|cent)

calculateBalances = !->
	Obs.observe !->
		Db.shared.iterate "transactions", (transaction) !->
			diff = Shared.transactionDiff(transaction.key())
			for userId, amount of diff
				balances.modify userId, (v) -> (v||0) + (diff[userId]||0)
			Obs.onClean !->
				for userId, amount of diff
					balances.modify userId, (v) -> (v||0) - (diff[userId]||0)

Dom.css
	'.selected:not(.tap)':
		background: '#f0f0f0'
	'.selectBlock:hover':
		background: '#e0e0e0 !important'
		border: '1px solid #d0d0d0 !important'
