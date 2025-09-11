import math
from rest_framework.response import Response
from rest_framework import status

class SuccessResponse(Response):
    def __init__(self, data=None, status=None,headers=None,page=None,total_items=None,limit=None):
        self.response_data={
            "message":"success",
            "data":data,
            "meta_data":{
                "total_page":math.ceil(total_items / limit),
                "current_page":page,
                "per_page":limit,
                "total":total_items
            } if page else None,
            "status":"success"
        }
        super().__init__(self.response_data, status,headers)


class FailureResponse(Response):
    def __init__(self, error=None, status=None,headers=None):
        self.response_data={
            "message":error,
            "data":[],
            "status":"failed"
        }
        super().__init__(self.response_data, status, headers)




