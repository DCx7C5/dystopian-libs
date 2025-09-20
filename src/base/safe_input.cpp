//
// Created by daen on 20.09.25.
//

#include "dystopian-libs/base/safe_input.h"

DL_BASE_NAMESPACE_BEGIN


class SafeInput {

public:
    SafeInput() = default;
    ~SafeInput() = default;

private:
    void with_unsecure_input(std::string* input);
};



DL_BASE_NAMESPACE_END