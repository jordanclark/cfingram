component {
	cfprocessingdirective( preserveCase=true );

	function init(
		required string apiEmail
	,	required string apiPassword
	,	required string apiMode= "test"
	,	required string apiVersion= "1"
	,	string defaultAccountID= ""
	) {
		this.apiEmail= arguments.apiEmail;
		this.apiPassword= arguments.apiPassword;
		this.apiMode= arguments.apiMode;
		this.apiVersion= arguments.apiVersion;
		this.apiUrl= ( arguments.apiMode == "live" ? "https://api.ingramentertainment.com" : "https://testapi.ingramentertainment.com" );
		this.defaultAccountID= arguments.defaultAccountID;
		this.authToken= "";
		this.authExpires= now();
		this.httpTimeOut= 120;
		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "ingram: " & arguments.input );
			} else {
				request.log( "ingram: (complex type)" );
				request.log( arguments.input );
			}
		} else {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="ingram", type="information" );
		}
		return;
	}

	function getAuthToken() {
		this.authToken= "";
		var out= this.apiRequest( api= "POST /authenticate", argumentCollection= {
			"email"= this.apiEmail
		,	"password"= this.apiPassword
		} );
		if ( out.success && structKeyExists( out.response, "auth_token" ) && len( out.response.auth_token ) ) {
			this.authToken= out.response.auth_token;
			this.authExpires= dateAdd( "h", 12, now() ); // expires in 12 hours
		}
		return out;
	}

	boolean function isAuthenticated() {
		if( dateCompare( this.authExpires, now() ) != 1 ) {
			// auth equal or greater then now
			this.authToken= "";
		}
		if( !len( this.authToken ) ) {
			return false;
		}
		return true;
	}

	function getAuthenticated() {
		if( dateCompare( this.authExpires, now() ) != 1 ) {
			// auth equal or greater then now
			this.authToken= "";
		}
		if( !len( this.authToken ) ) {
			auth= this.getAuthToken();
			if( !auth.success ) { 
				return auth;
			}
		}
		return nullValue();
	}

	function createOrder(
			required string account= this.defaultAccountID
		,	required string order_id
		,	required string item_number
		,	required numeric price
		,	required numeric qty
		,	required string ship_to_name
		,	required string ship_address1
		,	string ship_address2= ""
		,	required string ship_city
		,	required string ship_state
		,	required string ship_zip
		,	string ship_phone= ""
		,	required string carrier_code= ""
		,	required string service_class= ""
		,	string line_po= ""
	) {
		var o= { "orders"= [ { "order" = [ arguments ] } ] };
		if( len( arguments.line_po ) ) {
			return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/eorders", argumentCollection= o );
		}
		return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/orders", argumentCollection= o );
	}

	function addOrderToBatch(
		required array batch
	,	string account= this.defaultAccountID
	,	required string order_id
	,	required string item_number
	,	required numeric price
	,	required numeric qty
	,	required string ship_to_name
	,	required string ship_address1
	,	string ship_address2= ""
	,	required string ship_city
	,	required string ship_state
	,	required string ship_zip
	,	string ship_phone= ""
	,	required string carrier_code
	,	required string service_class
	,	string line_po= ""
	) {
		var b= arguments.batch;
		structDelete( arguments, "batch" );
		arrayAppend( b, arguments );
		return b;
	}

	function processOrderBatch( required array batch, boolean eorder= true ) {
		var b= { "orders"= [] };
		var lastOrder= "";
		var lastBatch= [];
		for( line in arguments.batch ) {
			if( lastOrder != line.order_id ) {
				if( arrayLen( lastBatch ) ) {
					arrayAppend( b.orders, { "order"= lastBatch } );
					lastBatch= [];
				}
				lastOrder= line.order_id;
			}
			arrayAppend( lastBatch, line );
		}
		if( arrayLen( lastBatch ) ) {
			arrayAppend( b.orders, { "order"= lastBatch } );
		}
		if( arguments.eorder ) {
			return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/eorders", argumentCollection= b );
		}
		return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/orders", argumentCollection= b );
	}

	function getOrderStatus() {
		return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/order_status" );
	}

	function getEOrderStatus( required string orderID, string account= this.defaultAccountID ) {
		var b= { "order_status"= [{
			"order"= {
				"account"= arguments.account
			,	"order_id"= arguments.orderID
			,	"ingram_order_id"= "Eorder"
			}
		}] };
		return this.getAuthenticated() ?: this.apiRequest( api= "POST /v#this.apiVersion#/order_status", argumentCollection= b );
	}

	function getInventory( required numeric id ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /v#this.apiVersion#/inventory/#arguments.id#" );
	}

	function getAllInventory() {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /v#this.apiVersion#/inventory" );
	}

	// groups: games, movies, dvd, bluray, audio, electronics, accessories
	function getInventoryGroup( required string group ) {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /v#this.apiVersion#/inventory_#arguments.group#" );
	}

	function getMovieDetails() {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /v#this.apiVersion#/movies?start=10" );
	}

	function getMusicDetails() {
		return this.getAuthenticated() ?: this.apiRequest( api= "GET /v#this.apiVersion#/movies" );
	}

	struct function apiRequest( required string api ) {
		var http= {};
		var dataKeys= 0;
		var item= "";
		var out= {
			success= false
		,	args= arguments
		,	error= ""
		,	status= ""
		,	json= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= this.apiUrl & listRest( arguments.api, " " )
		,	headers= {}
		};
		structDelete( out.args, "api" );
		if ( !structIsEmpty( out.args ) ) {
			out.body= serializeJSON( out.args );
			this.debugLog( out.body );
			out.headers[ "Accept" ]= "application/json";
			out.headers[ "Content-Type" ]= "application/json";
		}
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( len( this.authToken ) ) {
			out.headers[ "Authorization" ]= this.authToken;
		}
		if ( request.debug && request.dump ) {
			this.debugLog( out );
		}
		cftimer( type= "debug", label= "ingram request" ) {
			cfhttp( result= "http", method= out.verb, url= out.requestUrl, charset= "UTF-8", throwOnError= false, timeOut= this.httpTimeOut ) {
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type= "body", value= out.body );
				}
				for ( item in out.headers ) {
					cfhttpparam( name= item, type= "header", value= out.headers[ item ] );
				}
			}
		}
		// this.debugLog( http );
		out.response= toString( http.fileContent );
		//this.debugLog( out.response );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		this.debugLog( out.statusCode );
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.success= false;
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		if ( len( out.response ) && isJson( out.response ) ) {
			try {
				out.response= deserializeJSON( out.response );
			} catch (any cfcatch) {
				out.error= "JSON Error: " & (cfcatch.message?:"No catch message") & " " & (cfcatch.detail?:"No catch detail");
			}
		} else {
			out.error= "Response not JSON: #out.response#";
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		return out;
	}

}
